# AWS Billing Bar

A macOS menu bar app to monitor AWS billing costs across multiple accounts.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Multi-Account Support**: Monitor costs across multiple AWS accounts (dev, qa, prod, etc.)
- **Real-time Cost Tracking**: View month-to-date costs, last month costs, and forecasts
- **Service Breakdown**: See which AWS services are costing the most
- **Visual Trends**: 6-month cost history charts and daily spending graphs
- **Color-coded Accounts**: Easily distinguish between environments with color coding
- **Smart Icon**: Menu bar icon shows spending pace indicator
- **Auto-refresh**: Configurable refresh intervals (1min to 1hr)

## Requirements

- macOS 14.0 (Sonoma) or later
- AWS CLI configured with valid credentials
- AWS accounts must have Cost Explorer enabled

## Installation

### Building from Source

```bash
# Clone the repository
git clone https://github.com/masesor/AwsBillingBar.git
cd AwsBillingBar

# Build the app
swift build -c release

# Run
.build/release/AwsBillingBar
```

### Creating an App Bundle

```bash
# Build release
swift build -c release

# The executable will be at .build/release/AwsBillingBar
```

## AWS Setup

### Prerequisites

1. **Install AWS CLI**:
   ```bash
   brew install awscli
   ```

2. **Configure credentials**:
   ```bash
   aws configure
   # Or for named profiles:
   aws configure --profile myprofile
   ```

3. **Enable Cost Explorer**: Cost Explorer must be enabled in your AWS account. Visit the [AWS Cost Explorer console](https://console.aws.amazon.com/cost-management/home#/cost-explorer) to enable it.

### Required IAM Permissions

The AWS user/role needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetCostForecast"
            ],
            "Resource": "*"
        }
    ]
}
```

### Multi-Account Setup

For organizations with multiple AWS accounts:

1. Configure each account as a separate AWS CLI profile in `~/.aws/credentials`
2. Add each account in AwsBillingBar Settings
3. Assign colors to easily identify environments (e.g., green for dev, orange for qa, red for prod)

Example `~/.aws/credentials`:
```ini
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[dev]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[prod]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

## Usage

1. **Add an Account**: Click the menu bar icon → Settings → Add Account
2. **Configure**: Enter a display name, AWS account ID, and select the AWS CLI profile
3. **Monitor**: Click the menu bar icon to see your costs

### Menu Bar Icon

The menu bar icon shows:
- Dollar sign with AWS-style smile
- Bottom bar indicator showing spending pace:
  - **Green**: Under budget (spending less than expected)
  - **Orange**: On track
  - **Red**: Over budget (spending more than expected)

### Cost Cards

Click the icon to see:
- **Total MTD**: Combined month-to-date cost across all accounts
- **Change %**: Month-over-month change indicator
- **Per-account breakdown**: Individual costs per AWS account
- **Expandable details**: Click an account card to see:
  - 6-month trend chart
  - Top 5 services by cost
  - End-of-month forecast

## Architecture

```
AwsBillingBar/
├── Sources/
│   ├── AwsBillingBarCore/       # Core library (no UI)
│   │   ├── Models/              # Data models
│   │   ├── AWS/                 # AWS API integration
│   │   └── Stores/              # State management
│   └── AwsBillingBar/           # macOS app
│       ├── Controllers/         # Menu bar management
│       └── Views/               # SwiftUI views
└── Tests/
```

## Development

### Prerequisites

- Xcode 15.0+
- Swift 5.10+

### Building

```bash
swift build
```

### Testing

```bash
swift test
```

### Running

```bash
swift run AwsBillingBar
```

## Credits

- Uses [Sparkle](https://sparkle-project.org/) for updates
- Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for shortcuts

## License

MIT License - see LICENSE file for details.
