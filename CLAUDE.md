# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**Gotenx App** is a macOS/iOS application for running and visualizing tokamak fusion reactor simulations. It depends on **swift-gotenx** (Swift implementation of Google DeepMind's TORAX), which must be available at `../swift-gotenx`.

- **Platform**: macOS 26.0+, iOS 26.0+ (future)
- **Build System**: Xcode project (not Swift Package Manager)
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData (metadata) + File-based storage (simulation results)
- **Concurrency**: Swift 6.2 strict concurrency with actors

---

## Build and Test Commands

### Building

```bash
# Open in Xcode
open Gotenx.xcodeproj

# Build from command line
xcodebuild -scheme Gotenx -configuration Debug build

# Build for release
xcodebuild -scheme Gotenx -configuration Release build
```

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme Gotenx

# Run specific test
xcodebuild test -scheme Gotenx -only-testing:GotenxTests/GotenxTests/testExample
```

### Running the App

Use Xcode: ⌘R or Product → Run

---

## Critical Architecture Concepts

### 1. Data Model Compatibility (CRITICAL)

**swift-gotenx uses two separate type systems:**

#### Runtime Types (GPU tensors, NOT Codable)
- `CoreProfiles` - Contains `EvaluatedArray` (wraps `MLXArray` GPU tensor)
- `SimulationState` - Internal orchestrator state with `CoreProfiles`
- These **CANNOT** be JSON-encoded or stored

#### Storage Types (Codable, for serialization)
- `SerializableProfiles` - `[Float]` arrays, Codable
- `TimePoint` - Snapshot: time + `SerializableProfiles` + derived + diagnostics
- `SimulationResult` - Complete result: finalProfiles + statistics + `timeSeries: [TimePoint]?`

**Conversion Pattern:**
```swift
// Runtime → Storage
let serializable = coreProfiles.toSerializable()

// Storage → Runtime
let coreProfiles = CoreProfiles(from: serializable)

// State → Snapshot
let timePoint = state.toTimePoint()  // Uses toSerializable() internally
```

**NEVER attempt to encode `CoreProfiles` or `EvaluatedArray` directly.**

See `DATA_MODEL_COMPATIBILITY_ANALYSIS.md` for complete details.

---

### 2. Hybrid Storage Architecture

**SwiftData stores only lightweight metadata:**
- `Workspace`, `Simulation` models
- `SnapshotMetadata` (summary statistics for quick preview)
- Configuration data (encoded `SimulationConfiguration`)

**File system stores complete simulation data:**
```
~/Library/Application Support/Gotenx/simulations/
└── {simulation-id}/
    ├── config.json      (SimulationConfiguration)
    └── result.json      (SimulationResult with complete timeSeries)
```

**Why?** Storing thousands of snapshots in SwiftData causes database bloat and poor performance.

**Implementation:** `SimulationDataStore` actor handles all file I/O.

---

### 3. Actor Isolation Pattern

**SimulationOrchestrator** (from swift-gotenx) is an actor:

```swift
// ❌ WRONG - Cannot call from MainActor directly
@MainActor
func runSimulation() {
    let result = await orchestrator.run(...)  // Actor hop
    // UI update here ❌ - not on MainActor anymore
}

// ✅ CORRECT - Explicit MainActor.run
@MainActor
func runSimulation() {
    simulationTask = Task {
        let orchestrator = await SimulationOrchestrator(...)
        let result = try await orchestrator.run(...)

        await MainActor.run {
            // UI updates here ✅
            self.saveResults(result)
        }
    }
}
```

**Pattern:** Create orchestrator in background Task, hop back to MainActor for UI updates.

---

### 4. Correct SimulationOrchestrator Initialization

**The orchestrator requires SerializableProfiles, NOT CoreProfiles:**

```swift
// Convert configuration
let staticParams = try StaticRuntimeParams(from: config.runtime.static)
let dynamicParams = try DynamicRuntimeParams(from: config.runtime.dynamic)

// Create initial profiles (Codable)
let initialProfiles = SerializableProfiles.defaultITERLike(nCells: staticParams.mesh.nCells)

// Create transport and source models
let transport = createTransportModel(config.runtime.dynamic.transport)
let sources = createSourceModels(config.runtime.dynamic.sources)

// Initialize orchestrator
let orchestrator = await SimulationOrchestrator(
    staticParams: staticParams,
    initialProfiles: initialProfiles,  // ← SerializableProfiles, NOT CoreProfiles
    transport: transport,
    sources: sources,
    samplingConfig: .balanced
)

// Run simulation
let result = try await orchestrator.run(
    until: config.time.end,
    dynamicParams: dynamicParams
)
```

**Never** try to pass `CoreProfiles` to the orchestrator initializer.

---

### 5. Visualization with GotenxUI

**GotenxUI provides built-in conversion from SimulationResult to PlotData:**

```swift
// ✅ CORRECT - Use GotenxUI's built-in converter
let result = try dataStore.loadSimulationResult(simulationID: id)
let plotData = try PlotData(from: result)  // Already implemented!

// ❌ WRONG - Don't write custom conversion
// Custom conversion is unnecessary and error-prone
```

**Data flow:**
```
SimulationResult (from storage)
    ↓ GotenxUI conversion
PlotData (with unit conversions: eV→keV, m⁻³→10²⁰m⁻³)
    ↓
Swift Charts views
```

---

### 6. Error Handling (Production-Ready)

**Never use `try!` - always handle errors properly:**

```swift
// ❌ WRONG
let data = try! JSONEncoder().encode(profiles)

// ✅ CORRECT
do {
    let data = try JSONEncoder().encode(profiles)
    try data.write(to: url)
} catch {
    logger.error("Failed to save: \(error)")
    throw StorageError.fileWriteFailed(url, error)
}

// ✅ ALSO CORRECT - When fallback is acceptable
let data = try? JSONEncoder().encode(profiles) ?? Data()
```

**Use OSLog for logging:**
```swift
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "simulation")

logger.info("Starting simulation: \(name)")
logger.error("Simulation failed: \(error)")
logger.trace("Progress: \(Int(progress * 100))%")
```

---

### 7. Time-Based Throttling for UI Updates

**Use time-based (not frame-based) throttling:**

```swift
private var lastUpdateTime: Date = .distantPast
private let minUpdateInterval: TimeInterval = 0.1  // 100ms

func handleProgress(_ progress: ProgressInfo) {
    let now = Date()

    if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
        // Update UI
        self.simulationProgress = progress.ratio
        self.liveProfiles = progress.profiles
        lastUpdateTime = now
    }
}
```

**Why?** Frame-based throttling (`frame % 10 == 0`) leads to inconsistent update rates.

---

### 8. Liquid Glass Design System (iOS 26.0+)

**Liquid Glass** is Apple's new dynamic material that combines glass optical properties with fluid behavior. It's automatically adopted by standard SwiftUI components but can also be applied to custom views.

#### Key Characteristics

- **Dynamic Material**: Translucent, context-aware appearance
- **Fluid Animations**: Smooth morphing and transitions
- **Accessibility**: Auto-adapts to Reduce Motion/Transparency
- **Platform-Wide**: Consistent across macOS, iOS, iPadOS, watchOS, tvOS

#### Automatic Adoption

These Gotenx UI components get Liquid Glass automatically:

- `NavigationSplitView` (sidebar, inspector bars)
- `List` (sidebar navigation)
- `Toolbar` (top toolbar)
- `Picker` with `.segmented` style (inspector tabs)
- Standard buttons, toggles, sliders

**Action Required:** Remove custom backgrounds from these components to let Liquid Glass show through.

#### Manual Application to Custom Views

For custom controls in Gotenx (e.g., plot type selectors, custom buttons):

**Option 1: Use Glass Button Styles**
```swift
Button("Run Simulation") {
    viewModel.runSimulation()
}
.buttonStyle(.glassProminent)  // Primary action

Button("Export") {
    viewModel.exportResults()
}
.buttonStyle(.glass)  // Secondary action
```

**Option 2: Apply Glass Effect Directly**
```swift
// Custom control with glass effect
RoundedRectangle(cornerRadius: 12)
    .fill(Color.clear)
    .frame(width: 100, height: 44)
    .glassEffect(.interactive(), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
        Text("Custom")
            .foregroundStyle(.primary)
    }
```

**Option 3: Container for Multiple Morphing Shapes**
```swift
GlassEffectContainer(spacing: 12) {
    // Multiple views with glass effects
    // They will morph smoothly between each other
    ForEach(plotTypes) { type in
        plotTypeButton(type)
            .glassEffect(.interactive(), in: Capsule())
    }
}
```

#### Gotenx-Specific Implementations

**1. Toolbar Buttons (ToolbarView.swift)**
```swift
// Run button (primary action)
Button {
    Task { try? await viewModel.runSimulation(sim) }
} label: {
    Label("Run", systemImage: "play.fill")
}
.buttonStyle(.glassProminent)  // ← Prominent glass style
.disabled(viewModel.isSimulationRunning)

// Pause/Stop buttons (secondary actions)
Button {
    viewModel.pauseSimulation()
} label: {
    Label("Pause", systemImage: "pause.fill")
}
.buttonStyle(.glass)  // ← Standard glass style
```

**2. Plot Type Selector (PlotTypeSelectorView.swift)**
```swift
GlassEffectContainer(spacing: 8) {
    HStack(spacing: 8) {
        ForEach(PlotType.allCases, id: \.self) { type in
            Button(type.displayName) {
                plotViewModel.selectPlotType(type)
            }
            .buttonStyle(.glass)
        }
    }
}
```

**3. Sidebar List (SidebarView.swift)**
```swift
// Liquid Glass applied automatically
List(selection: $selectedSimulation) {
    Section("Simulations") {
        ForEach(workspace.simulations) { simulation in
            SimulationRowView(simulation: simulation)
        }
    }
}
// ✅ NO custom backgrounds - let Liquid Glass show
```

**4. Inspector Tabs (InspectorView.swift)**
```swift
// Segmented picker gets Liquid Glass automatically
Picker("Inspector", selection: $selectedTab) {
    Label("Plot", systemImage: "chart.bar").tag(InspectorTab.plot)
    Label("Data", systemImage: "tablecells").tag(InspectorTab.data)
    Label("Config", systemImage: "gearshape").tag(InspectorTab.config)
}
.pickerStyle(.segmented)
// ✅ Automatic Liquid Glass appearance
```

**5. Background Extension for Edge-to-Edge Content**
```swift
// In MainCanvasView.swift - for hero images or full-width plots
ScrollView {
    GotenxPlotView(data: plotData, config: plotConfig)
        .backgroundExtensionEffect()  // ← Extends beneath sidebar/inspector
}
```

#### Best Practices for Gotenx

**DO ✅**

1. **Use standard button styles**
   - `.glassProminent` for primary actions (Run, Save)
   - `.glass` for secondary actions (Export, Settings)

2. **Remove custom toolbar backgrounds**
   ```swift
   // ❌ Remove this
   .toolbarBackground(.visible, for: .navigationBar)
   .toolbarBackground(Color.blue, for: .navigationBar)

   // ✅ Let system apply Liquid Glass
   .toolbar { ... }
   ```

3. **Let NavigationSplitView handle sidebar/inspector**
   ```swift
   NavigationSplitView {
       SidebarView()  // ✅ Automatic glass
   } content: {
       MainCanvasView()
   } detail: {
       InspectorView()  // ✅ Automatic glass
   }
   ```

4. **Test with accessibility settings**
   - System Settings → Accessibility → Display → Reduce Transparency
   - System Settings → Accessibility → Motion → Reduce Motion

**DON'T ❌**

1. **Don't overuse custom glass effects**
   - Limit to 2-3 custom controls maximum
   - Standard components already have glass

2. **Don't layer glass on glass**
   ```swift
   // ❌ Avoid nesting glass effects
   VStack {
       controlA.glassEffect(...)
       controlB.glassEffect(...)
   }
   .glassEffect(...)  // ❌ Too many layers
   ```

3. **Don't apply to content**
   ```swift
   // ❌ Wrong - content should NOT have glass
   GotenxPlotView(...)
       .glassEffect(...)  // ❌ Plots are content, not controls

   // ✅ Correct - apply to controls only
   Button("Export Plot") { }
       .buttonStyle(.glass)  // ✅ Control has glass
   ```

#### Migration Checklist

When implementing Gotenx UI:

- [ ] Remove all custom `.background()` modifiers from toolbars
- [ ] Remove custom `.toolbarBackground()` calls
- [ ] Use `.buttonStyle(.glass)` for toolbar buttons
- [ ] Use `.buttonStyle(.glassProminent)` for primary actions
- [ ] Keep plot content glass-free (content layer)
- [ ] Test with Reduce Transparency enabled
- [ ] Test with Reduce Motion enabled

#### Related APIs

```swift
// Button styles
.buttonStyle(.glass)
.buttonStyle(.glassProminent)
.buttonStyle(GlassButtonStyle(.interactive()))

// View modifiers
.glassEffect(.interactive(), in: Shape)
.glassEffect(.interactive(false), in: Shape)

// Containers
GlassEffectContainer(spacing: CGFloat?) { content }

// Transitions
.transition(.glassEffectTransition(.matchedGeometry))
.transition(.glassEffectTransition(.materialize))

// Background extension (for split views)
.backgroundExtensionEffect()
```

#### Resources

- [Liquid Glass Overview](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Applying Liquid Glass to Custom Views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- WWDC 2025 Session 219: Meet Liquid Glass
- WWDC 2025 Session 323: Build a SwiftUI app with the new design

---

## Key Reference Documents

### Must-Read Before Implementation

1. **GOTENX_APP_SPECIFICATION.md** (v1.1)
   - Complete app specification
   - UI/UX design (3-column layout)
   - View and ViewModel architecture
   - **NOTE:** Contains data model errors - see v2.0 updates

2. **GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md** (CRITICAL)
   - Fixes all data model compatibility issues
   - Updated SimulationDataStore implementation
   - Corrected AppViewModel and PlotViewModel
   - **Read this BEFORE implementing any storage or simulation code**

3. **DATA_MODEL_COMPATIBILITY_ANALYSIS.md**
   - Explains CoreProfiles vs SerializableProfiles
   - Documents all Codable vs non-Codable types
   - Shows correct conversion patterns
   - **Reference when working with swift-gotenx types**

4. **QUICKSTART.md**
   - 30-minute setup guide
   - Step-by-step implementation

### swift-gotenx Integration

Located at `../swift-gotenx/`:

- **README.md** - swift-gotenx overview
- **GOTENX_APP_INTEGRATION.md** - Integration requirements for this app
- **Sources/Gotenx/Core/** - Core types (CoreProfiles, DerivedQuantities)
- **Sources/Gotenx/Orchestration/** - SimulationOrchestrator, SimulationState, TimePoint
- **Sources/GotenxUI/Models/** - PlotData, PlotData3D

---

## Common Pitfalls to Avoid

### ❌ DON'T

1. **Don't encode CoreProfiles directly**
   ```swift
   try JSONEncoder().encode(coreProfiles)  // ❌ FAILS - NOT Codable
   ```

2. **Don't pass CoreProfiles to storage**
   ```swift
   dataStore.save(coreProfiles, ...)  // ❌ WRONG TYPE
   ```

3. **Don't write custom PlotData conversion**
   ```swift
   // ❌ Unnecessary - GotenxUI already has this
   func convertToPlotData(_ snapshots: [...]) -> PlotData { ... }
   ```

4. **Don't update UI from background actor**
   ```swift
   Task {
       let result = await orchestrator.run(...)
       self.status = .completed  // ❌ Not on MainActor
   }
   ```

5. **Don't use try! for I/O operations**
   ```swift
   try! data.write(to: url)  // ❌ Will crash on error
   ```

6. **Don't add custom backgrounds to navigation elements**
   ```swift
   // ❌ Interferes with Liquid Glass
   .toolbarBackground(.visible, for: .navigationBar)
   .toolbarBackground(Color.blue, for: .navigationBar)
   ```

7. **Don't apply glass effects to content**
   ```swift
   // ❌ Plots are content, not controls
   GotenxPlotView(...)
       .glassEffect(.interactive(), in: RoundedRectangle(cornerRadius: 12))
   ```

### ✅ DO

1. **Use SerializableProfiles for storage**
   ```swift
   let serializable = coreProfiles.toSerializable()  // ✅ Codable
   try JSONEncoder().encode(serializable)
   ```

2. **Store SimulationResult from orchestrator**
   ```swift
   let result = try await orchestrator.run(...)  // ✅ Returns SimulationResult
   try dataStore.saveSimulationResult(result, simulationID: id)
   ```

3. **Use GotenxUI's PlotData converter**
   ```swift
   let result = try dataStore.loadSimulationResult(simulationID: id)
   let plotData = try PlotData(from: result)  // ✅ Built-in
   ```

4. **Hop to MainActor for UI updates**
   ```swift
   await MainActor.run {
       self.status = .completed  // ✅ On MainActor
   }
   ```

5. **Handle errors with do-catch or try?**
   ```swift
   do {
       try data.write(to: url)
   } catch {
       logger.error("Failed: \(error)")
   }
   ```

6. **Use standard button styles for Liquid Glass**
   ```swift
   Button("Run") { viewModel.runSimulation() }
       .buttonStyle(.glassProminent)  // ✅ Primary action

   Button("Export") { viewModel.export() }
       .buttonStyle(.glass)  // ✅ Secondary action
   ```

7. **Let system apply Liquid Glass to navigation**
   ```swift
   NavigationSplitView {
       SidebarView()  // ✅ Automatic Liquid Glass
   } content: {
       MainCanvasView()
   } detail: {
       InspectorView()  // ✅ Automatic Liquid Glass
   }
   ```

---

## Project Structure (High-Level)

```
Gotenx/
├── Gotenx/                         # App source
│   ├── GotenxApp.swift            # App entry point, SwiftData setup
│   ├── ContentView.swift          # Root view (to be replaced)
│   ├── Models/                    # SwiftData models (to be created)
│   │   ├── Workspace.swift
│   │   ├── Simulation.swift
│   │   └── ConfigurationPreset.swift
│   ├── ViewModels/                # @Observable ViewModels (to be created)
│   │   ├── AppViewModel.swift
│   │   ├── PlotViewModel.swift
│   │   └── ConfigViewModel.swift
│   ├── Views/                     # SwiftUI views (to be created)
│   │   ├── SidebarView.swift
│   │   ├── MainCanvasView.swift
│   │   ├── InspectorView.swift
│   │   └── ToolbarView.swift
│   └── Services/                  # Data services (to be created)
│       └── SimulationDataStore.swift
├── GotenxTests/                   # Unit tests
├── GotenxUITests/                 # UI tests
└── Documentation/                 # Specification and analysis
    ├── GOTENX_APP_SPECIFICATION.md (v1.1)
    ├── GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md (CRITICAL)
    ├── DATA_MODEL_COMPATIBILITY_ANALYSIS.md
    └── QUICKSTART.md
```

---

## Implementation Status

**Current State:** Xcode project scaffold with default SwiftUI template

**Next Steps (from QUICKSTART.md):**

1. ✅ Xcode project created
2. ⏳ Add swift-gotenx package dependency
3. ⏳ Implement SwiftData models (Workspace, Simulation)
4. ⏳ Create SimulationDataStore actor
5. ⏳ Implement ViewModels (AppViewModel, PlotViewModel)
6. ⏳ Build UI (3-column layout: Sidebar, MainCanvas, Inspector)
7. ⏳ Integrate SimulationOrchestrator
8. ⏳ Add GotenxUI plotting

**Follow GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md for all implementation.**

---

## swift-gotenx Dependency

**Location:** Must be at `../swift-gotenx` (sibling directory)

**Required Products:**
- `Gotenx` - Core simulation engine
- `GotenxPhysics` - Physics models (QLKNN, transport)
- `GotenxUI` - Plotting and visualization

**Add via Xcode:**
1. Project → Target → General → Frameworks
2. Add Package Dependency → Add Local
3. Navigate to `~/Desktop/swift-gotenx`
4. Select all three products

**Verify:** `import Gotenx`, `import GotenxPhysics`, `import GotenxUI` should autocomplete.

---

## Key Types Reference

### From swift-gotenx

**Runtime (NOT Codable):**
- `CoreProfiles` - Ion/electron temperature, density, poloidal flux (GPU tensors)
- `EvaluatedArray` - Wrapper for `MLXArray`
- `SimulationState` - Internal orchestrator state

**Storage (Codable):**
- `SerializableProfiles` - Codable version of CoreProfiles
- `TimePoint` - Snapshot: time + profiles + derived + diagnostics
- `SimulationResult` - Final result: finalProfiles + statistics + timeSeries
- `SimulationConfiguration` - Complete simulation config
- `DerivedQuantities` - Scalar metrics (Q, τE, βN, etc.)
- `NumericalDiagnostics` - Convergence and conservation metrics

**Models:**
- `SimulationOrchestrator` - Main simulation actor
- `TransportModel` - Protocol for transport models (QLKNN, Bohm, etc.)
- `SourceModel` - Protocol for heating/current drive sources

### App-Specific (SwiftData)

- `Workspace` - Top-level container
- `Simulation` - Simulation metadata (no large data)
- `SnapshotMetadata` - Lightweight snapshot summary
- `ConfigurationPreset` - Saved configurations

### App-Specific (Actors)

- `SimulationDataStore` - File-based storage for simulation results

---

## Final Notes

- **Always check DATA_MODEL_COMPATIBILITY_ANALYSIS.md** when uncertain about types
- **Never encode CoreProfiles** - use SerializableProfiles instead
- **Use GotenxUI's PlotData converter** - don't write your own
- **Follow v2.0 updates document** - v1.1 spec has critical errors
- **Test with both successful and failed simulations** to ensure error handling works
- **Remove custom backgrounds from navigation** - let Liquid Glass show automatically
- **Use `.glass` and `.glassProminent` button styles** - don't create custom glass effects unless necessary
- **Test with Reduce Transparency and Reduce Motion enabled** - ensure graceful fallback

---

**Last Updated:** 2025-10-22
**Specification Version:** 2.0 (with compatibility fixes)
**Design System:** Liquid Glass (iOS 26.0+)
