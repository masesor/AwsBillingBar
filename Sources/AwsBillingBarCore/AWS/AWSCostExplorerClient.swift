import Foundation
import Logging

/// Client for AWS Cost Explorer API
public actor AWSCostExplorerClient {
    private let logger = Logger(label: "AwsBillingBar.CostExplorer")
    private let credentialsManager: AWSCredentialsManager
    private let session: URLSession

    private let serviceName = "ce"
    private let apiVersion = "2017-10-25"

    public init(credentialsManager: AWSCredentialsManager) {
        self.credentialsManager = credentialsManager
        self.session = URLSession.shared
    }

    /// Fetch billing data for an account
    public func fetchBilling(for account: AWSAccount) async throws -> BillingSnapshot {
        let credentials = try await credentialsManager.getCredentials(for: account.profileName)

        // Get date ranges
        // Note: AWS Cost Explorer end dates are EXCLUSIVE, so we use tomorrow to include today's costs
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth)!
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: startOfMonth)!

        // Fetch data sequentially (AWS Cost Explorer has rate limits)
        let mtdData = try await getCostAndUsage(
            credentials: credentials,
            region: account.region,
            startDate: startOfMonth,
            endDate: tomorrow,
            granularity: "DAILY"
        )

        let lastMonthData = try await getCostAndUsage(
            credentials: credentials,
            region: account.region,
            startDate: startOfLastMonth,
            endDate: startOfMonth,
            granularity: "MONTHLY"
        )

        let serviceData = try await getCostByService(
            credentials: credentials,
            region: account.region,
            startDate: startOfMonth,
            endDate: tomorrow
        )

        let historyData = try await getCostAndUsage(
            credentials: credentials,
            region: account.region,
            startDate: sixMonthsAgo,
            endDate: tomorrow,
            granularity: "MONTHLY"
        )

        let forecast = try await getCostForecast(
            credentials: credentials,
            region: account.region
        )

        // Parse results
        let dailyCosts = parseDailyCosts(from: mtdData)
        let monthToDateCost = dailyCosts.reduce(0) { $0 + $1.cost }
        let lastMonthCost = parseMonthlyTotal(from: lastMonthData)
        let monthlyCosts = parseMonthlyCosts(from: historyData)

        let dayOfMonth = calendar.component(.day, from: today)
        let dailyAverage = dayOfMonth > 0 ? monthToDateCost / Double(dayOfMonth) : 0

        return BillingSnapshot(
            accountId: account.accountId,
            accountName: account.name,
            monthToDateCost: monthToDateCost,
            lastMonthCost: lastMonthCost,
            forecastedMonthCost: forecast,
            dailyAverageCost: dailyAverage,
            costByService: parseServiceCosts(from: serviceData, total: monthToDateCost),
            dailyCosts: dailyCosts,
            monthlyCosts: monthlyCosts,
            currency: "USD"
        )
    }


    private func getCostAndUsage(
        credentials: AWSCredentials,
        region: String,
        startDate: Date,
        endDate: Date,
        granularity: String
    ) async throws -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let body: [String: Any] = [
            "TimePeriod": [
                "Start": formatter.string(from: startDate),
                "End": formatter.string(from: endDate)
            ],
            "Granularity": granularity,
            "Metrics": ["UnblendedCost"]
        ]

        return try await makeRequest(
            credentials: credentials,
            region: region,
            action: "GetCostAndUsage",
            body: body
        )
    }

    private func getCostByService(
        credentials: AWSCredentials,
        region: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let body: [String: Any] = [
            "TimePeriod": [
                "Start": formatter.string(from: startDate),
                "End": formatter.string(from: endDate)
            ],
            "Granularity": "MONTHLY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": [
                ["Type": "DIMENSION", "Key": "SERVICE"]
            ]
        ]

        return try await makeRequest(
            credentials: credentials,
            region: region,
            action: "GetCostAndUsage",
            body: body
        )
    }

    private func getCostForecast(
        credentials: AWSCredentials,
        region: String
    ) async throws -> Double? {
        let calendar = Calendar.current
        let today = Date()

        guard let endOfMonth = calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: today),
                month: calendar.component(.month, from: today) + 1,
                day: 1
            )
        ) else { return nil }

        // Can't forecast if we're at the end of the month
        if calendar.isDate(today, inSameDayAs: endOfMonth) {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let body: [String: Any] = [
            "TimePeriod": [
                "Start": formatter.string(from: tomorrow),
                "End": formatter.string(from: endOfMonth)
            ],
            "Metric": "UNBLENDED_COST",
            "Granularity": "MONTHLY"
        ]

        do {
            let response = try await makeRequest(
                credentials: credentials,
                region: region,
                action: "GetCostForecast",
                body: body
            )

            if let total = response["Total"] as? [String: Any],
               let amount = total["Amount"] as? String {
                return Double(amount)
            }
        } catch {
            // Forecast may fail if not enough data
            logger.warning("Could not get forecast: \(error)")
        }

        return nil
    }


    private func makeRequest(
        credentials: AWSCredentials,
        region: String,
        action: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        let endpoint = "https://ce.\(region).amazonaws.com/"
        guard let url = URL(string: endpoint) else {
            throw AWSError.invalidResponse
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSInsightsIndexService.\(action)", forHTTPHeaderField: "X-Amz-Target")

        // Sign the request
        let signedRequest = try signRequest(
            request: request,
            credentials: credentials,
            region: region
        )

        let (data, response) = try await session.data(for: signedRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AWSError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AWSError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AWSError.invalidResponse
        }

        return json
    }

    private func signRequest(
        request: URLRequest,
        credentials: AWSCredentials,
        region: String
    ) throws -> URLRequest {
        var signedRequest = request

        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        signedRequest.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        signedRequest.setValue("ce.\(region).amazonaws.com", forHTTPHeaderField: "Host")

        if let token = credentials.sessionToken {
            signedRequest.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        // Create canonical request
        let method = "POST"
        let canonicalUri = "/"
        let canonicalQuerystring = ""

        let signedHeaders = credentials.sessionToken != nil
            ? "content-type;host;x-amz-date;x-amz-security-token;x-amz-target"
            : "content-type;host;x-amz-date;x-amz-target"

        let payloadHash = sha256Hash(data: request.httpBody ?? Data())

        var canonicalHeaders = """
            content-type:\(request.value(forHTTPHeaderField: "Content-Type") ?? "")
            host:ce.\(region).amazonaws.com
            x-amz-date:\(amzDate)
            """

        if let token = credentials.sessionToken {
            canonicalHeaders += "\nx-amz-security-token:\(token)"
        }

        canonicalHeaders += "\nx-amz-target:\(request.value(forHTTPHeaderField: "X-Amz-Target") ?? "")"

        let canonicalRequest = """
            \(method)
            \(canonicalUri)
            \(canonicalQuerystring)
            \(canonicalHeaders)

            \(signedHeaders)
            \(payloadHash)
            """

        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(serviceName)/aws4_request"
        let stringToSign = """
            \(algorithm)
            \(amzDate)
            \(credentialScope)
            \(sha256Hash(string: canonicalRequest))
            """

        // Calculate signature
        let kDate = hmacSHA256(key: "AWS4\(credentials.secretAccessKey)".data(using: .utf8)!, data: dateStamp)
        let kRegion = hmacSHA256(key: kDate, data: region)
        let kService = hmacSHA256(key: kRegion, data: serviceName)
        let kSigning = hmacSHA256(key: kService, data: "aws4_request")
        let signature = hmacSHA256(key: kSigning, data: stringToSign).map { String(format: "%02x", $0) }.joined()

        // Create authorization header
        let authorization = "\(algorithm) Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        signedRequest.setValue(authorization, forHTTPHeaderField: "Authorization")

        return signedRequest
    }


    private func parseDailyCosts(from response: [String: Any]) -> [DailyCost] {
        guard let results = response["ResultsByTime"] as? [[String: Any]] else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        return results.compactMap { result -> DailyCost? in
            guard let period = result["TimePeriod"] as? [String: String],
                  let startString = period["Start"],
                  let date = formatter.date(from: startString),
                  let total = result["Total"] as? [String: [String: String]],
                  let unblended = total["UnblendedCost"],
                  let amountString = unblended["Amount"],
                  let amount = Double(amountString) else {
                return nil
            }
            return DailyCost(date: date, cost: amount)
        }
    }

    private func parseMonthlyTotal(from response: [String: Any]) -> Double {
        guard let results = response["ResultsByTime"] as? [[String: Any]],
              let firstResult = results.first,
              let total = firstResult["Total"] as? [String: [String: String]],
              let unblended = total["UnblendedCost"],
              let amountString = unblended["Amount"] else {
            return 0
        }
        return Double(amountString) ?? 0
    }

    private func parseMonthlyCosts(from response: [String: Any]) -> [MonthlyCost] {
        guard let results = response["ResultsByTime"] as? [[String: Any]] else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        return results.compactMap { result -> MonthlyCost? in
            guard let period = result["TimePeriod"] as? [String: String],
                  let startString = period["Start"],
                  let total = result["Total"] as? [String: [String: String]],
                  let unblended = total["UnblendedCost"],
                  let amountString = unblended["Amount"],
                  let amount = Double(amountString) else {
                return nil
            }

            // Convert date to month string
            let monthString = String(startString.prefix(7)) // "2024-01"

            // Check if this is the current month (incomplete)
            let isComplete = !startString.hasPrefix(getCurrentMonthPrefix())

            return MonthlyCost(month: monthString, cost: amount, isComplete: isComplete)
        }
    }

    private func parseServiceCosts(from response: [String: Any], total: Double) -> [ServiceCost] {
        guard let results = response["ResultsByTime"] as? [[String: Any]],
              let firstResult = results.first,
              let groups = firstResult["Groups"] as? [[String: Any]] else {
            return []
        }

        var serviceCosts = groups.compactMap { group -> ServiceCost? in
            guard let keys = group["Keys"] as? [String],
                  let serviceName = keys.first,
                  let metrics = group["Metrics"] as? [String: [String: String]],
                  let unblended = metrics["UnblendedCost"],
                  let amountString = unblended["Amount"],
                  let amount = Double(amountString),
                  amount > 0 else {
                return nil
            }

            let percentage = total > 0 ? (amount / total) * 100 : 0
            return ServiceCost(serviceName: serviceName, cost: amount, percentage: percentage)
        }

        // Sort by cost descending
        serviceCosts.sort { $0.cost > $1.cost }

        return serviceCosts
    }

    private func getCurrentMonthPrefix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }


    private func sha256Hash(string: String) -> String {
        sha256Hash(data: string.data(using: .utf8)!)
    }

    private func sha256Hash(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: String) -> Data {
        hmacSHA256(key: key, data: data.data(using: .utf8)!)
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress,
                    key.count,
                    dataBuffer.baseAddress,
                    data.count,
                    &hash
                )
            }
        }
        return Data(hash)
    }
}

// CommonCrypto imports
import CommonCrypto
