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

### 6. MLX Lazy Evaluation and eval() (CRITICAL)

**MLX uses lazy evaluation** - operations build a computation graph without executing until `eval()` is explicitly called.

#### What eval() Does

**eval() forces execution of pending operations in the computation graph and materializes results.**

**Key points:**
- eval() does **NOT** clear or destroy the graph
- eval() executes pending computations and stores results
- The graph persists after eval(), but materialized results prevent redundant recomputation
- Calling eval() again on the same arrays becomes a no-op if no new operations were added

#### When to Call eval()

**RULE 1: Always eval() before calling .item()**

```swift
// ❌ WRONG - .item() on unevaluated array
let norm = MLX.norm(x)
let value = norm.item(Float.self)  // May return stale/incorrect value

// ✅ CORRECT - eval() before .item()
let norm = MLX.norm(x)
eval(norm)
let value = norm.item(Float.self)  // Correct value
```

**RULE 2: Call eval() in loops to prevent graph accumulation**

MLX uses lazy evaluation - operations build a computation graph without executing immediately.
In loops, without eval(), each iteration extends the graph, making it progressively larger.
Calling eval() forces computation and materializes results, preventing the graph from growing indefinitely.

**Important**: eval() does NOT clear the graph - it executes pending operations and materializes results.
The graph persists, but materialized results prevent redundant recomputation in subsequent iterations.

```swift
// ❌ WRONG - Graph accumulates over 200 iterations
for i in 0..<200 {
    let (_, vjpResult) = vjp(fn, primals: [x], cotangents: [cotangent])
    jacobianRows.append(vjpResult[0])  // Graph keeps growing!
}
// Result: 0.06s → 1.0s (17x slower by iteration 200)

// ✅ CORRECT - eval() materializes result each iteration
for i in 0..<200 {
    let (_, vjpResult) = vjp(fn, primals: [x], cotangents: [cotangent])
    eval(vjpResult[0])  // Materialize result to prevent graph growth
    jacobianRows.append(vjpResult[0])
}
// Result: Consistent 0.06s per iteration
```

**RULE 3: Batch eval() calls for multiple arrays**

```swift
// ❌ INEFFICIENT - Multiple separate eval() calls
eval(a)
eval(b)
eval(c)

// ✅ EFFICIENT - Single batched eval()
eval(a, b, c)  // Executes graph once for all arrays
```

#### Common Anti-Patterns

**Anti-Pattern 1: Over-using eval()**

Calling eval() too frequently prevents MLX from optimizing the computation graph.
MLX can fuse operations and reduce overhead when building larger graphs.

```swift
// ❌ WRONG - eval() after every operation prevents graph optimization
let a = x + y
eval(a)  // Forces execution, prevents fusion with next operation
let b = a * 2
eval(b)  // Forces execution, prevents fusion
let c = b.sum()
eval(c)  // Only this one is actually needed

// ✅ CORRECT - eval() only when necessary
let a = x + y
let b = a * 2
let c = b.sum()
eval(c)  // Single eval() allows MLX to optimize: fuse(add, mul, sum)
let result = c.item(Float.self)
```

**Anti-Pattern 2: Missing eval() before array indexing**

```swift
// ❌ WRONG - Indexing unevaluated array in loop
for i in 0..<n {
    let value = array[i]  // Lazy slice - not evaluated!
    let scalar = value.item(Float.self)  // May be incorrect
}

// ✅ CORRECT - eval() before .item()
for i in 0..<n {
    let value = array[i]
    eval(value)  // Force evaluation
    let scalar = value.item(Float.self)  // Correct
}

// ✅ BETTER - Evaluate entire array once
eval(array)
for i in 0..<n {
    let scalar = array[i].item(Float.self)  // Fast access
}
```

**Anti-Pattern 3: Mutating arrays without eval()**

```swift
// ❌ WRONG - Mutation may not take effect
var x = MLXArray.zeros([n])
for i in 0..<n {
    x[i] = MLXArray(computeValue(i))  // Lazy assignment
}
// x might still be zeros!

// ✅ CORRECT - eval() to materialize mutations
var x = MLXArray.zeros([n])
for i in 0..<n {
    x[i] = MLXArray(computeValue(i))
}
eval(x)  // Ensure all mutations are applied
```

#### Real-World Example: Newton-Raphson Jacobian Computation

```swift
// ✅ CORRECT - From FlattenedState.swift
public func computeJacobianViaVJP(
    _ residualFn: @escaping (MLXArray) -> MLXArray,
    _ x: MLXArray
) -> MLXArray {
    let n = x.shape[0]
    var jacobianTranspose: [MLXArray] = []

    for i in 0..<n {
        let cotangent = MLXArray.zeros([n])
        cotangent[i] = MLXArray(1.0)

        let (_, vjpResult) = vjp(
            wrappedFn,
            primals: [x],
            cotangents: [cotangent]
        )

        // ✅ CRITICAL: Prevent graph accumulation
        eval(vjpResult[0])

        jacobianTranspose.append(vjpResult[0])
    }

    return MLX.stacked(jacobianTranspose, axis: 0).T
}
```

**Without `eval(vjpResult[0])`**:
- Iteration 0: 0.06s
- Iteration 100: 0.5s (8x slower)
- Iteration 200: 1.0s (17x slower)

**With `eval(vjpResult[0])`**:
- All iterations: 0.06s (constant)

#### Performance Impact

| Scenario | Without eval() | With eval() | Speedup |
|----------|---------------|-------------|---------|
| vjp loop (200 iterations) | ~120s | ~12s | **10x** |
| Nested loops | Exponential growth | Constant | **100x+** |
| Large arrays (.item() calls) | Incorrect results | Correct | N/A |

#### MLX Optimization Strategy - Graph Fusion

**CRITICAL**: Calling eval() too frequently prevents MLX from optimizing your computation graph.

**How MLX optimizes:**
MLX fuses multiple operations into a single GPU kernel when it sees a large computation graph.

```swift
// ✅ GOOD: Operations chain → MLX fuses into 1 GPU kernel
let a = x + y      // lazy
let b = a * 2      // lazy
let c = sqrt(b)    // lazy
eval(c)  // ← Fuses (x + y) * 2 → sqrt into single kernel

// Result: 1 GPU call, 1 memory transfer

// ❌ BAD: eval() breaks the chain → 3 separate GPU kernels
let a = x + y
eval(a)  // ❌ GPU call #1
let b = a * 2
eval(b)  // ❌ GPU call #2
let c = sqrt(b)
eval(c)  // ❌ GPU call #3

// Result: 3 GPU calls, 3 memory transfers (3x slower!)
```

**Golden Rule: Let graphs grow across function boundaries**

```swift
// ✅ GOOD: Functions return lazy graphs
func computeA(x: MLXArray) -> MLXArray {
    return x * 2 + 1  // lazy - graph continues
}

func computeB(a: MLXArray) -> MLXArray {
    return a * 3 + 2  // lazy - graph continues
}

// Caller decides when to eval()
let a = computeA(x: input)  // lazy
let b = computeB(a: a)      // lazy - graphs connected
eval(b)  // ← Single fused kernel: ((x * 2 + 1) * 3 + 2)

// ❌ BAD: eval() inside functions breaks fusion
func computeA(x: MLXArray) -> MLXArray {
    let result = x * 2 + 1
    eval(result)  // ❌ Breaks graph here
    return result
}

func computeB(a: MLXArray) -> MLXArray {
    let result = a * 3 + 2
    eval(result)  // ❌ Separate kernel
    return result
}

// Result: 2 GPU calls (cannot fuse)
```

**Cost of unnecessary eval()**

| Impact | Without early eval() | With early eval() | Difference |
|--------|---------------------|-------------------|------------|
| GPU kernel calls | 1 | N (per eval) | N× overhead |
| Memory transfers | Minimal | Intermediate results | Bandwidth waste |
| Operation fusion | Yes | No | 2-10× slower |
| Memory buffers | Optimized | Extra allocations | Memory pressure |

**When to eval() - Decision flowchart:**

```
Got a computation result
    ↓
Need actual values? (.item(), .asArray())
    YES → eval() required
    NO  ↓
Passing to another function?
    YES → Don't eval() (let graphs chain)
    NO  ↓
Wrapping in EvaluatedArray?
    YES → EvaluatedArray(evaluating:) (auto eval)
    NO  ↓
Inside independent loop? (results don't affect next iteration)
    YES → eval() (prevent graph accumulation)
    NO  → Don't eval()
```

#### Debugging Tips

**Check for graph accumulation:**
1. Add timing logs in loops
2. If time increases each iteration → missing eval()
3. Use `eval()` after operations that will be used in next iteration

**Verify correctness:**
1. Always `eval()` before `.item()` or `.asArray()`
2. If results are NaN/Inf/wrong → check for missing eval()
3. Use `print()` on MLXArray → triggers implicit eval()

---

### 7. Error Handling (Production-Ready)

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

### 8. Time-Based Throttling for UI Updates

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

### 9. Liquid Glass Design System (iOS 26.0+)

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

8. **Don't forget eval() in MLX loops**
   ```swift
   // ❌ Graph accumulates, causing exponential slowdown
   for i in 0..<200 {
       let (_, vjpResult) = vjp(fn, primals: [x], cotangents: [cotangent])
       jacobianRows.append(vjpResult[0])  // Missing eval()!
   }
   // Result: 0.06s → 1.0s (17x slower by iteration 200)
   ```

9. **Don't call .item() on unevaluated arrays**
   ```swift
   // ❌ May return incorrect/stale values
   let norm = MLX.norm(x)
   let value = norm.item(Float.self)  // Missing eval()!
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

8. **Call eval() in MLX loops to prevent graph accumulation**
   ```swift
   // ✅ Constant performance across all iterations
   for i in 0..<200 {
       let (_, vjpResult) = vjp(fn, primals: [x], cotangents: [cotangent])
       eval(vjpResult[0])  // ✅ Materialize result to prevent graph growth
       jacobianRows.append(vjpResult[0])
   }
   // Result: Consistent 0.06s per iteration
   ```

9. **Always eval() before .item()**
   ```swift
   // ✅ Correct value returned
   let norm = MLX.norm(x)
   eval(norm)  // ✅ Force evaluation
   let value = norm.item(Float.self)
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
- **CRITICAL: Always eval() before .item()** - missing eval() causes incorrect results
- **CRITICAL: Call eval() in MLX loops** - prevents graph accumulation and exponential slowdown
- **Test with both successful and failed simulations** to ensure error handling works
- **Remove custom backgrounds from navigation** - let Liquid Glass show automatically
- **Use `.glass` and `.glassProminent` button styles** - don't create custom glass effects unless necessary
- **Test with Reduce Transparency and Reduce Motion enabled** - ensure graceful fallback

---

**Last Updated:** 2025-10-26
**Specification Version:** 2.2 (with MLX eval() best practices and optimization strategy)
**Design System:** Liquid Glass (iOS 26.0+)
