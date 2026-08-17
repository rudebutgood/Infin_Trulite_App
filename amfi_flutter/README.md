# Infin Trulite

A lightweight, professional Flutter application for tracking Indian Mutual Fund portfolios using live AMFI data and Indmoney XLSX statement imports.

## Features

- **Live NAV Tracking**: Fetches real-time Mutual Fund NAVs directly from the AMFI (Association of Mutual Funds in India) API.
- **Consolidated Portfolio**: Import multiple Indmoney XLSX or CSV statements to see a combined view of your family's holdings.
- **Interactive Performance View**:
  - **Net Profit**: View total market value vs. invested value with overall gain percentages.
  - **1-Day Returns**: One-tap toggle to see absolute and percentage gains for the current day.
- **Smart Data Mapping**: Automatically joins portfolio holdings with live AMFI data using ISINs.
- **Advanced Filtering**: Filter by Mutual Fund house (AMC), Category (Direct/Regular), and search by scheme name.
- **Pinned Holdings**: Funds you own are automatically pinned to the top of the main NAV list with a "Wallet" indicator.
- **Indian Currency Format**: All values are displayed using the Indian numbering system (Lakhs/Crores).

## Technical Overview

- **Framework**: Flutter (Dart)
- **Database**: Local SQLite (sqflite) for high-performance offline access and history tracking.
- **Networking**: Parallel API fetching with SSL certificate bypass for AMFI compatibility.
- **Parsing**: Robust XLSX/CSV parsing with support for Indmoney-specific schemas.
- **Architecture**: Service-based repository pattern for clean separation of data and UI.

## Getting Started

1. **Build**: `flutter build apk --release --split-per-abi`
2. **Import**: Go to the Portfolio tab and select your Indmoney XLSX statement.
3. **Analyze**: Tap the values on the right to flip between Net Gain and 1-Day Gain views.

---
*Developed as a high-density, performance-first financial utility.*
