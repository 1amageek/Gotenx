# Gotenx App - Quick Start Guide

**Goal**: Get the Gotenx App project set up and running in 30 minutes

---

## Prerequisites

- **macOS 15.0+** (Sequoia or later)
- **Xcode 16.0+** with Swift 6.2
- **swift-gotenx** cloned and building successfully

---

## Step 1: Create Xcode Project (5 min)

### 1.1 Create Project

```bash
cd ~/Desktop
# You already have Gotenx/ directory from previous setup
cd Gotenx
```

The project structure is already initialized. Verify:

```bash
ls -la
# Should see:
# - Gotenx/                 (App source)
# - Gotenx.xcodeproj/       (Xcode project)
# - GotenxTests/
# - GotenxUITests/
```

### 1.2 Open in Xcode

```bash
open Gotenx.xcodeproj
```

---

## Step 2: Add swift-gotenx Dependency (5 min)

### 2.1 Add Package Dependency

1. In Xcode, select project "Gotenx" in navigator
2. Select "Gotenx" target
3. Go to "General" tab → "Frameworks, Libraries, and Embedded Content"
4. Click "+" → "Add Package Dependency..."
5. Choose "Add Local..."
6. Navigate to `~/Desktop/swift-gotenx`
7. Click "Add Package"

### 2.2 Select Products

When prompted, select:
- ✅ **Gotenx** (Core library)
- ✅ **GotenxPhysics**
- ✅ **GotenxUI**

Click "Add Package"

### 2.3 Verify Import

In `Gotenx/GotenxApp.swift`:

```swift
import SwiftUI
import SwiftData
import Gotenx        // ✅ Should autocomplete
import GotenxPhysics // ✅ Should autocomplete
import GotenxUI      // ✅ Should autocomplete

@main
struct GotenxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Build (⌘B) to verify no errors.

---

## Step 3: Implement Data Models (10 min)

### 3.1 Create Models Directory

In Xcode:
1. Right-click "Gotenx" folder → New Group → "Models"

### 3.2 Create Workspace.swift

**File**: `Gotenx/Models/Workspace.swift`

```swift
import SwiftData
import Foundation

@Model
class Workspace {
    var id: UUID
    var name: String
    var simulations: [Simulation] = []
    var createdAt: Date
    var modifiedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
```

### 3.3 Create Simulation.swift

**File**: `Gotenx/Models/Simulation.swift`

```swift
import SwiftData
import Foundation
import Gotenx

@Model
class Simulation {
    var id: UUID
    var name: String
    var configuration: Data
    var status: SimulationStatus
    var snapshots: [SimulationSnapshot] = []
    var createdAt: Date
    var modifiedAt: Date

    var workspace: Workspace?

    init(name: String, configuration: SimulationConfiguration) {
        self.id = UUID()
        self.name = name
        self.configuration = (try? JSONEncoder().encode(configuration)) ?? Data()
        self.status = .draft
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

enum SimulationStatus: Codable {
    case draft
    case running(progress: Double)
    case completed
    case failed(error: String)
}
```

### 3.4 Create SimulationSnapshot.swift

**File**: `Gotenx/Models/SimulationSnapshot.swift`

```swift
import SwiftData
import Foundation
import Gotenx

@Model
class SimulationSnapshot {
    var id: UUID
    var time: Float
    var profiles: Data
    var derivedQuantities: Data?
    var timestamp: Date
    var isBookmarked: Bool

    var simulation: Simulation?

    init(time: Float, profiles: CoreProfiles, derived: DerivedQuantities? = nil) {
        self.id = UUID()
        self.time = time
        self.profiles = (try? JSONEncoder().encode(profiles)) ?? Data()
        self.derivedQuantities = derived.flatMap { try? JSONEncoder().encode($0) }
        self.timestamp = Date()
        self.isBookmarked = false
    }
}
```

---

## Step 4: Create Basic UI (10 min)

### 4.1 Update GotenxApp.swift

**File**: `Gotenx/GotenxApp.swift`

```swift
import SwiftUI
import SwiftData

@main
struct GotenxApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Simulation.self,
            SimulationSnapshot.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### 4.2 Update ContentView.swift

**File**: `Gotenx/ContentView.swift`

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                ForEach(workspaces) { workspace in
                    Section(workspace.name) {
                        ForEach(workspace.simulations) { simulation in
                            Text(simulation.name)
                        }
                    }
                }
            }
            .navigationTitle("Simulations")
            .toolbar {
                Button("New", systemImage: "plus") {
                    createDefaultWorkspace()
                }
            }

        } detail: {
            // Main canvas
            VStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Select a simulation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if workspaces.isEmpty {
                createDefaultWorkspace()
            }
        }
    }

    private func createDefaultWorkspace() {
        let workspace = Workspace(name: "Default")
        modelContext.insert(workspace)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Workspace.self, inMemory: true)
}
```

---

## Step 5: Build and Run (2 min)

### 5.1 Build

Press **⌘B** or Product → Build

Should compile with no errors.

### 5.2 Run

Press **⌘R** or Product → Run

You should see:
```
┌─────────────────┬──────────────────────┐
│ Simulations     │                      │
│                 │   📊                 │
│ Default         │   Select a           │
│                 │   simulation         │
│ [+ New]         │                      │
└─────────────────┴──────────────────────┘
```

---

## Step 6: Verify swift-gotenx Integration (3 min)

Add a test simulation to verify the integration works.

### 6.1 Create Test Configuration

**File**: `Gotenx/Models/TestConfiguration.swift`

```swift
import Gotenx

extension SimulationConfiguration {
    static var minimal: SimulationConfiguration {
        // TODO: Replace with actual minimal configuration
        // For now, create a placeholder
        SimulationConfiguration(
            runtime: RuntimeConfiguration(
                static: StaticConfiguration(/* ... */),
                dynamic: DynamicConfiguration(/* ... */)
            ),
            time: TimeConfiguration(
                start: 0.0,
                end: 1.0,
                initialDt: 1e-5
            ),
            output: OutputConfiguration(
                directory: "/tmp/gotenx",
                format: .json
            )
        )
    }
}
```

**Note**: You'll need to fill in the actual configuration structure based on swift-gotenx's API. Check `Examples/Configurations/minimal.json` for reference.

### 6.2 Test Creating Simulation

Update `ContentView.swift`:

```swift
private func createDefaultWorkspace() {
    let workspace = Workspace(name: "Default")
    modelContext.insert(workspace)

    // Add a test simulation
    let config = SimulationConfiguration.minimal
    let simulation = Simulation(name: "Test ITER-like", configuration: config)
    simulation.workspace = workspace
    workspace.simulations.append(simulation)
}
```

Build and run. You should see "Test ITER-like" in the sidebar.

---

## Next Steps

### Immediate (Today)

1. ✅ Project setup complete
2. ⏳ Implement `AppViewModel` (see `GOTENX_APP_SPECIFICATION.md` Section 5.1)
3. ⏳ Create `SidebarView` with simulation list
4. ⏳ Add "New Simulation" sheet

### This Week

1. ⏳ Implement toolbar with Run/Pause/Stop buttons
2. ⏳ Integrate `SimulationOrchestrator` for running simulations
3. ⏳ Add real-time progress updates
4. ⏳ Implement `MainCanvasView` with basic plotting

### Next Week

1. ⏳ Add `InspectorView` with plot/data/config inspectors
2. ⏳ Implement time slider and animation
3. ⏳ Add export functionality
4. ⏳ Polish UI and add error handling

---

## Troubleshooting

### Issue: "Cannot find 'Gotenx' in scope"

**Solution**:
1. Verify swift-gotenx builds successfully: `cd ../swift-gotenx && swift build`
2. Clean build folder: Product → Clean Build Folder (⇧⌘K)
3. Re-add package dependency

### Issue: "Type 'CoreProfiles' does not conform to protocol 'Codable'"

**Solution**: swift-gotenx needs updates. See `GOTENX_APP_INTEGRATION.md` for required changes.

### Issue: SwiftData errors on launch

**Solution**:
1. Delete app container: `~/Library/Containers/com.yourteam.Gotenx`
2. Rebuild and run

---

## Resources

- **Full Specification**: `GOTENX_APP_SPECIFICATION.md`
- **swift-gotenx Integration**: `../swift-gotenx/GOTENX_APP_INTEGRATION.md`
- **swift-gotenx Docs**: `../swift-gotenx/README.md`, `../swift-gotenx/CLAUDE.md`

---

## Development Tips

### Use Live Preview

Enable SwiftUI previews for faster iteration:

```swift
#Preview {
    ContentView()
        .modelContainer(for: Workspace.self, inMemory: true)
}
```

### Debug SwiftData

Print model context changes:

```swift
modelContext.insertedModelsArray.forEach { print("Inserted: \($0)") }
```

### Test with Sample Data

Create mock simulations for testing:

```swift
extension Workspace {
    static var preview: Workspace {
        let workspace = Workspace(name: "Preview")
        let config = SimulationConfiguration.minimal
        let sim = Simulation(name: "ITER-like", configuration: config)
        workspace.simulations.append(sim)
        return workspace
    }
}
```

---

**Estimated Total Time**: 30-35 minutes

**Next Steps**: Continue with Phase 2 of implementation roadmap (see specification)

**Questions?** Refer to full specification document or swift-gotenx documentation.
