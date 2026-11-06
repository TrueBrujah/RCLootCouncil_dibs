# Quickstart: Centralized Feature Registry

How to use the feature registry, and how to add a feature to it.

## Using the registry

### List every feature

```lua
for _, feature in ipairs(Dibs.FeatureRegistry.ListFeatures()) do
  print(feature.id, feature.label, feature.required and "REQUIRED" or "OPTIONAL")
end
```

### Check whether a feature is usable

```lua
if Dibs.FeatureRegistry.IsEnabled("greatVault") then
  -- the feature may proceed
end
```

`IsEnabled` returns the boolean and, when the feature is not enabled, the
reason code. An unknown identifier returns `false` and `FEATURE_UNKNOWN`, so
the check fails closed.

### Enforce a feature at an entry point

```lua
local allowed, reason, message = Dibs.FeatureRegistry.RequireEnabled("dryRun")
if not allowed then
  return nil, reason, message
end
```

This is the single enforcement gate. Every optional feature entry point should
pass through it.

### Inspect the effective state

```lua
local state = Dibs.FeatureRegistry.GetEffectiveState("historicalReconciliation")
-- state.enabled
-- state.reasonCode   -- e.g. "FEATURE_DISABLED_BY_DEPENDENCY"
-- state.dependency   -- e.g. "rclootcouncil"
```

### Inspect the dependency graph

```lua
Dibs.FeatureRegistry.GetDependencies("historicalReconciliation")
-- { id = "historicalReconciliation", direct = { "rclootcouncil" }, transitive = { "rclootcouncil" } }

Dibs.FeatureRegistry.GetDependents("rclootcouncil")
-- { "historicalReconciliation" }
```

### Preview a change

```lua
local preview = Dibs.FeatureRegistry.PreviewState("requests", { requests = false })
-- preview.enabled == false
-- preview.reasonCode == "FEATURE_DISABLED_BY_POLICY"
```

The preview never mutates anything.

### Diagnose the configuration

```lua
for _, line in ipairs(Dibs.FeatureRegistry.GetDiagnostics()) do
  print(line)
end
-- "Registry v1 policy r3 adopted=true"
-- "announcements: ENABLED"
-- "requests: DISABLED (FEATURE_DISABLED_BY_POLICY)"
```

### Read the change history

```lua
local history = Dibs.FeatureRegistry.GetChangeHistory(20)
```

The history is read from the operational policy audit log, so it cannot
diverge from the canonical record.

## Changing the configuration

Only the verified Guild Master or an explicitly authorized policy writer may
change the guild feature configuration.

```lua
local changed, reason = Dibs.OperationalPolicy.ChangeModules({ requests = false }, nil, "guild decision")
```

`ChangeModules` validates the patch, applies the dependency rule, creates a
new canonical revision, and announces it to the guild. It returns `false` and
a reason code when the change is refused, and the current policy is left
untouched.

To check authority first:

```lua
local allowed, reason = Dibs.OperationalPolicy.CanChangeModules(nil)
```

## Adding a feature to the catalogue

1. **Verify the dependency edges.** Trace the actual call sites. A module
   header comment is not evidence of a dependency.

2. **Decide the class.** If the canonical accounting path depends on the
   feature, it is a **required service**, not an optional feature. A guild
   that could turn it off would break the accounting path.

3. **Add the definition** to `CORE_MODULE_DEFINITIONS` or
   `MODULE_DEFINITIONS` in `src/modules/OperationalPolicy.lua`:

   ```lua
   { key = "myFeature", label = "My Feature", category = "workflow",
     description = "What this feature does for the guild.",
     requires = "rclootcouncil" },
   ```

4. **Do not change the record format.** The overlay stays sparse. A new
   definition does not change the content hash of an existing record, and no
   migration is needed.

5. **Increment `CATALOGUE_VERSION`.** It is published through
   `Policy.GetCatalogueVersion()` and lets a peer detect that its catalogue
   differs.

6. **Enforce it.** Add the gate at every entry point of the feature:

   ```lua
   if Dibs.FeatureRegistry and type(Dibs.FeatureRegistry.IsEnabled) == "function" then
     if Dibs.FeatureRegistry.IsEnabled("myFeature") ~= true then
       return nil, "MODULE_DISABLED_MY_FEATURE"
     end
   end
   ```

7. **Add the entry point to the enforcement coverage matrix** in
   `traceability.md` and to the table in `docs/developer/feature-catalog.md`.

8. **Write a discriminating test.** The test must fail when the enforcement
   is removed.

9. **Regenerate the documentation** with
   `scripts/Generate-DibsDocs.ps1 -Generate` and verify it with `-Check`.

## Adding a dependency edge

1. Verify the edge in the code.
2. Add `requires` to the dependent definition.
3. The interface cascade and the dependent list update automatically, because
   they read the canonical catalogue.
4. Add a test that turns the dependency off and asserts the dependent's
   effective state and the refusal reason code.

## Related documents

- [Feature catalogue](../../docs/developer/feature-catalog.md)
- [Feature dependencies](../../docs/developer/feature-dependencies.md)
- [Feature configuration](../../docs/developer/feature-configuration.md)
- [Feature synchronization](../../docs/developer/feature-sync-protocol.md)
