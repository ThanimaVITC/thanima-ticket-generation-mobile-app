# Thanima Attendance App

A Flutter-based mobile application for managing event attendance using secure QR codes. Designed for seamless on-site verification.

## Features

- **Secure QR Scanning**: Scans hash-based encrypted QR codes to verify attendees instantly.
- **Real-time Verification**: Validates tickets against the server database to prevent forgery and duplication.
- **Event Context**: Automatically checks if the scanned ticket belongs to the currently selected event.
- **Attendance Marking**: Marks attendance in real-time with visual and haptic feedback.
- **Dynamic Configuration**: Configure server URL dynamically within the app.
- **Authentication**: Secure login system for authorized volunteers/admins.
- **Hardware Control**: Integrated flashlight toggle and camera switching (front/back).

## Getting Started

1.  **Configure Server**: on first launch, enter your backend server URL (e.g., `http://192.168.1.5:3000`).
2.  **Login**: Use your admin credentials.
3.  **Select Event**: Choose the active event you are managing.
4.  **Scan**: Point camera at attendee tickets. Green checkmark confirms success.

## Tech Stack

- **Framework**: Flutter
- **Scanning**: `mobile_scanner`
- **Networking**: `http` with secure cookie management
- **Storage**: `flutter_secure_storage` for tokens and config used to store sensitive data
