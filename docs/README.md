# Gotenx Documentation

**Last Updated**: 2025-10-27

---

## Quick Start

### 🚀 New Developers
1. [README.md](../README.md) - Project overview
2. [QUICKSTART.md](guides/QUICKSTART.md) - 30-minute setup guide
3. [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) - Current status

### 💻 Implementation Work
1. [CLAUDE.md](../CLAUDE.md) - Development guidelines for AI assistants
2. [DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md) - Critical data model info
3. [Implementation guides](implementation/) - Patterns and best practices

---

## Documentation Structure

```
Gotenx/
├── CLAUDE.md                    # AI assistant project guide
├── README.md                    # Project overview
├── IMPLEMENTATION_STATUS.md     # Current status (2025-10-27)
└── docs/
    ├── README.md               # This file
    ├── guides/                 # 3 files - Essential guides
    └── implementation/         # 7 files - Implementation patterns
```

---

## 📚 Guides

### Essential Reading

1. **[QUICKSTART.md](guides/QUICKSTART.md)** ⭐
   - 30-minute setup guide
   - Step-by-step implementation
   - Best for new developers

2. **[GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md](guides/GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md)** ⭐
   - **CRITICAL**: Data model compatibility fixes
   - Updated SimulationDataStore implementation
   - Corrected AppViewModel and PlotViewModel
   - **Read this BEFORE implementing storage or simulation code**

3. **[DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md)**
   - CoreProfiles vs SerializableProfiles
   - Codable vs non-Codable types
   - Correct conversion patterns
   - Reference when working with swift-gotenx types

---

## 🛠️ Implementation Guides

### UI & Charts

1. **[CHART_IMPLEMENTATION_GUIDE.md](implementation/CHART_IMPLEMENTATION_GUIDE.md)** ⭐
   - Swift Charts best practices
   - @ChartContentBuilder pattern
   - Type-checker timeout solutions
   - Real-world examples

2. **[GRID_LAYOUT_IMPLEMENTATION.md](implementation/GRID_LAYOUT_IMPLEMENTATION.md)**
   - 2-column LazyVGrid implementation
   - Layout configuration details
   - Performance metrics

3. **[CONSOLE_VIEW_DESIGN.md](implementation/CONSOLE_VIEW_DESIGN.md)**
   - Console view specification
   - Log display and filtering
   - Real-time updates

### Features & Strategy

4. **[PLOT_FEATURES_STRATEGY.md](implementation/PLOT_FEATURES_STRATEGY.md)**
   - Phase 1-5 plot implementation strategy
   - Plot type system design
   - Feature breakdown

5. **[PHASE_MIGRATION_GUIDE.md](implementation/PHASE_MIGRATION_GUIDE.md)**
   - Migration between development phases
   - Breaking changes
   - Upgrade paths

### Integration

6. **[SIMULATION_INTEGRATION_DESIGN.md](implementation/SIMULATION_INTEGRATION_DESIGN.md)**
   - Simulation orchestrator integration
   - Data flow architecture
   - Progress reporting

7. **[SIMULATION_RUNNABLE_INTEGRATION.md](implementation/SIMULATION_RUNNABLE_INTEGRATION.md)**
   - SimulationRunnable protocol
   - Task management
   - Error handling patterns

---

## 📖 Reading Order for New Developers

### Day 1: Project Overview
1. [README.md](../README.md) - Project overview
2. [CLAUDE.md](../CLAUDE.md) - Development guidelines
3. [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) - Current state

### Day 2: Architecture & Data Model
1. [GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md](guides/GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md) - Critical specification
2. [DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md) - Data model deep dive

### Day 3: Implementation
1. [QUICKSTART.md](guides/QUICKSTART.md) - Setup guide
2. [CHART_IMPLEMENTATION_GUIDE.md](implementation/CHART_IMPLEMENTATION_GUIDE.md) - Chart patterns
3. [GRID_LAYOUT_IMPLEMENTATION.md](implementation/GRID_LAYOUT_IMPLEMENTATION.md) - Layout patterns

---

## 🔑 Key Concepts

### Data Model (CRITICAL)

**swift-gotenx uses two separate type systems:**

#### Runtime Types (GPU tensors, NOT Codable)
- `CoreProfiles` - Contains `EvaluatedArray` (wraps `MLXArray` GPU tensor)
- `SimulationState` - Internal orchestrator state with `CoreProfiles`
- **CANNOT** be JSON-encoded or stored

#### Storage Types (Codable, for serialization)
- `SerializableProfiles` - `[Float]` arrays, Codable
- `TimePoint` - Snapshot: time + `SerializableProfiles` + derived + diagnostics
- `SimulationResult` - Complete result: finalProfiles + statistics + timeSeries

**NEVER attempt to encode CoreProfiles directly.**

See [DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md) for complete details.

### Architecture Patterns

1. **Hybrid Storage**
   - SwiftData: Lightweight metadata (Workspace, Simulation)
   - File system: Complete simulation data (JSON)

2. **Actor Isolation**
   - SimulationOrchestrator is an actor
   - Use `await MainActor.run` for UI updates
   - Proper Task creation patterns

3. **Type Safety**
   - Enum-based plot types
   - Compile-time verification
   - No string literals

4. **Lazy Loading**
   - LazyVGrid for plot display
   - Efficient memory usage
   - Smooth scrolling

---

## 📊 Current Implementation Status

**As of 2025-10-27**:

### ✅ Completed Features
- ✅ 11 profile plot types
- ✅ 6 time series scalar plots
- ✅ 2-column grid layout (LazyVGrid)
- ✅ Y-axis scale control (linear/log)
- ✅ Dynamic plot selection
- ✅ Type-safe architecture
- ✅ @ChartContentBuilder optimization

### ⏳ Pending
- ⏳ Add swift-gotenx package dependency (required)
- ⏳ Build and test
- ⏳ Integration testing

### 🎯 Next Steps
1. Add swift-gotenx package in Xcode
2. Build project (⌘B)
3. Verify plot features
4. Test simulation execution

See [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) for complete details.

---

## 🛡️ Code Quality Standards

### Required Practices
- ✅ No `try!` or force unwraps
- ✅ Bounds checking for array access
- ✅ OSLog for logging (not print)
- ✅ @Observable pattern (not ObservableObject)
- ✅ Modern SwiftUI APIs

### Best Practices
- Use enum-based type systems
- Prefer editing existing files over creating new ones
- Break complex views into computed properties
- Document public APIs
- Write clear commit messages

See [CLAUDE.md](../CLAUDE.md) for full guidelines.

---

## 🆘 Common Issues & Solutions

### 1. Type-checker timeout in Chart views
**Solution**: [CHART_IMPLEMENTATION_GUIDE.md](implementation/CHART_IMPLEMENTATION_GUIDE.md)
- Use @ChartContentBuilder pattern
- Break Chart body into computed properties

### 2. CoreProfiles encoding error
**Solution**: [DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md)
- Use SerializableProfiles instead
- Never encode CoreProfiles directly

### 3. Actor isolation errors
**Solution**: [GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md](guides/GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md)
- Use proper `await MainActor.run` pattern
- Create background Tasks correctly

### 4. Build errors from swift-gotenx
- Check package version compatibility
- Ensure local package path is correct: `~/Desktop/swift-gotenx`
- Verify all three products are added: GotenxCore, GotenxPhysics, GotenxUI

---

## 📚 External References

### Apple Documentation
- [Swift Charts](https://developer.apple.com/documentation/Charts)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [@Observable](https://developer.apple.com/documentation/observation/observable)

### swift-gotenx
- Location: `../swift-gotenx/`
- README: `../swift-gotenx/README.md`
- Integration Guide: `../swift-gotenx/GOTENX_APP_INTEGRATION.md`

---

## 📝 File Index

### Root Level
- [CLAUDE.md](../CLAUDE.md) - AI assistant project guide
- [README.md](../README.md) - Project overview
- [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) - Current status

### Guides (3 files)
- [QUICKSTART.md](guides/QUICKSTART.md)
- [GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md](guides/GOTENX_APP_SPECIFICATION_v2.0_UPDATES.md)
- [DATA_MODEL_COMPATIBILITY_ANALYSIS.md](guides/DATA_MODEL_COMPATIBILITY_ANALYSIS.md)

### Implementation (7 files)
- [CHART_IMPLEMENTATION_GUIDE.md](implementation/CHART_IMPLEMENTATION_GUIDE.md)
- [GRID_LAYOUT_IMPLEMENTATION.md](implementation/GRID_LAYOUT_IMPLEMENTATION.md)
- [CONSOLE_VIEW_DESIGN.md](implementation/CONSOLE_VIEW_DESIGN.md)
- [PLOT_FEATURES_STRATEGY.md](implementation/PLOT_FEATURES_STRATEGY.md)
- [PHASE_MIGRATION_GUIDE.md](implementation/PHASE_MIGRATION_GUIDE.md)
- [SIMULATION_INTEGRATION_DESIGN.md](implementation/SIMULATION_INTEGRATION_DESIGN.md)
- [SIMULATION_RUNNABLE_INTEGRATION.md](implementation/SIMULATION_RUNNABLE_INTEGRATION.md)

---

**Total Documentation**: 13 files (3 root + 3 guides + 7 implementation)

**Last Updated**: 2025-10-27
**Maintained By**: Claude Code
