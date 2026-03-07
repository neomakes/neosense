# iPhone 16 Pro Multi-Modal Logger: Edge AI Testbed 📱⚡️

[![Swift](https://img.shields.io/badge/Swift-5.10+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![Device](https://img.shields.io/badge/Device-iPhone_16_Pro-black.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A lightweight, minimal, yet powerful multi-modal sensor logging application designed specifically for the **iPhone 16 Pro**.

This project goes beyond merely collecting data; its primary goal is to serve as an **Offline-First Testbed for Orchestration AI engines**. By capturing raw, irregular time-series data streams shaped by hardware thermal throttling and OS scheduling, it provides the perfect "noisy" dataset required to train robust continuous-time models like **NCP (Neural Circuit Policies)** and **LTC (Liquid Time-Constant)** networks.

---

## 🌟 Key Features

- **Offline-First & Graceful Degradation**: Operates completely offline to observe pure hardware limits. Instead of preventing frame drops, the app explicitly captures frequency fluctuations $X(t)$ caused by CPU load and thermal throttling.
- **Attention-driven Sampling $C(t)$ Ready**: Built with an architectural backbone to allow upper-layer logic to actively adjust sensing frequencies based on "Information Gain," pushing beyond passive logging into **Active Sensing**.
- **Multi-CSV Architecture**: Eliminates I/O lock contention by isolating $800Hz$ motion data and $1Hz$ GPS data into independent, highly efficient asynchronous CSV streams.
- **Comprehensive Sensor Coverage**:
  - **Motion**: `800Hz` Accelerometer & `200Hz` HDR Gyroscope via `CMBatchedSensorManager`.
  - **Vision & AR**: `ARKit` Face Tracking (BlendShapes), LiDAR Depth Maps, and Raw Camera metadata.
  - **Environment**: Barometer, Ambient Light Sensor (ALS), and Color Spectrum.
  - **Location**: Dual-Frequency GPS (L1+L5) and precise Magnetometer data.
  - **Context**: `thermalState`, Battery, CPU/Mem load.

---

## 🧪 Testing Methodology (The Core Value)

The true value of this testbed lies in its two-phased testing methodology, designed to capture both the "ideal" hardware limits and "chaos" states:

- **Phase 1: Isolating & Ideal State**
  - Toggle specific sensors individually using the dashboard switches.
  - **Goal**: Validate baseline pipeline integrity and observe hardware capabilities at ideal constant frequencies ($C$ Hz) with near-zero latency.
- **Phase 2: Interaction & Chaos State (Stress Test)**
  - Trigger the 🔴 **[START ALL]** button to ignite all sensors simultaneously.
  - **Goal**: Force memory buffer overflows and thermal state spikes (`Serious` / `Critical`). This induces OS scheduling delays, causing the target $800Hz$ to drop and warp into irregular $X(t)$ time-series data—perfectly simulating real-world sensor interference and Jitter.
- **Phase 3: Visualization & Model Injection**
  - Export the logs to Python/Jupyter to visualize the correlation between `thermal_state` and data `dropout`. Inject this noisy context into NCP/LTC models to validate their robustness.

---

## 📊 Time-Series Minimum Schema

To perfectly map delays, jitters, and dropouts, every single row across all Multi-CSV files enforces a strict meta-schema layer:

| Column          | Description & Analysis Purpose                                                                                        |
| :-------------- | :-------------------------------------------------------------------------------------------------------------------- |
| `hw_timestamp`  | Hardware-level creation time. Used to calculate real frequency $X(t)$ and **Jitter**.                                 |
| `sys_timestamp` | OS/App-level arrival time. <br/>`sys_timestamp` - `hw_timestamp` = **OS Scheduling Delay**.                           |
| `target_c_hz`   | The target Constant frequency requested by the `LogController`.                                                       |
| `thermal_state` | Real-time device temp (`0: Nominal` to `3: Critical`). Used to analyze the correlation between heat and data dropout. |

---

## 🏗 Architecture Layers

The app is decoupled into four primary layers to guarantee UI thread stability while ingesting thousands of events per second:

1. **Core Application Layer**: SwiftUI Dashboard, Permission Manager, and central `LogController` Orchestrator.
2. **Sensor Management Layer**: Independent provider classes (`MotionLogger`, `LocationEnvironmentLogger`, `VisionAudioLogger`).
3. **System Introspection Layer**: Monitors device health (`SystemMetricsMonitor`) to trigger feedback loops.
4. **Storage & Persistence Layer**: A non-blocking `BufferQueue` mapped into a `DataFileWriter` (Multi-CSV format).

## 🛠 Prerequisites & Getting Started

> **CRITICAL**: You _must_ run this on a physical **iPhone 16 Pro / Pro Max** (A17/A18 Pro chips). The Simulator cannot emulate the true thermal, hardware limits, or scheduling jitters that this project aims to capture. iOS 17.0+ is required.

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/iPhone16Pro-Logger.git
   cd iPhone16Pro-Logger
   ```
2. **Open in Xcode**
   Open `iPhoneLogger.xcodeproj` in Xcode and configure your Development Team in Signing & Capabilities.
3. **Build and Run (⌘+R)**
   Grant all prompted permissions upon first launch and start analyzing $X(t)$!

## 📁 Directory Structure

```text
iphoneLogger/
├── README.md              # Project overview and instructions
├── docs/                  # Planning and design documents (PRD, UX/UI, Arc. Diagram)
├── App/                   # App entry point and lifecycle management
├── Managers/              # Sensor core modules (Motion, Location, Vision, etc.)
├── Models/                # Data schemas and model definitions
├── Utils/                 # Utility functions (file saving, formatting, export)
└── Views/                 # SwiftUI dashboard and UI components
```

## 📄 License & Contribution

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
Pull Requests are extremely welcome! If you find a new private API or a more efficient logging pipeline, please feel free to contribute.

---

_Disclaimer: Heavy logging of high-frequency sensors will drain battery quickly and purposely increase device temperature for stress testing. Use with caution._
