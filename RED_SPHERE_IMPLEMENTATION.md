# Red Sphere Visual Markers Implementation Guide

## Current Status

✅ **Structure Implemented:**
- `_addMarkerVisual()` method added to both `upload_anchor_screen.dart` and `navigation_screen.dart`
- Visual marker tracking with `_visualMarkerIds` list
- Cleanup methods for removing visual markers
- Position logging for debugging

⚠️ **Pending:**
- Actual 3D sphere rendering (requires correct `ar_flutter_plugin` API)

## Implementation Steps

### Step 1: Check ar_flutter_plugin API

The `ar_flutter_plugin` version 0.7.3 API for adding 3D objects needs to be confirmed. Check:

1. **Plugin Documentation:** https://pub.dev/packages/ar_flutter_plugin
2. **Source Code:** Check `ARObjectManager` class methods
3. **Examples:** Look for example projects using the plugin

### Step 2: Choose Implementation Method

#### Option A: Using Built-in Shapes (Preferred)

If `ar_flutter_plugin` supports ARCore built-in shapes:

```dart
// In _addMarkerVisual method, replace the TODO section with:
final arNode = ARNode(
  name: markerId,
  type: NodeType.sphere, // or ArCoreSphere
  position: position,
  scale: Vector3(0.15, 0.15, 0.15), // 15cm sphere
  materials: [
    ARMaterial(
      color: Colors.red.withOpacity(0.8),
      metallic: 0.0,
    ),
  ],
);

await _objectManager!.addNode(arNode, anchor: anchor);
```

#### Option B: Using 3D Model File

If built-in shapes aren't available:

1. **Add a sphere GLB file:**
   - Download from: https://github.com/KhronosGroup/glTF-Sample-Models
   - Place in `assets/sphere.glb`
   - Update `pubspec.yaml`:
     ```yaml
     flutter:
       assets:
         - assets/sphere.glb
     ```

2. **Update code:**
   ```dart
   await _objectManager!.addObject(
     objectUrl: 'assets/sphere.glb',
     position: position,
     scale: Vector3(0.15, 0.15, 0.15),
     anchor: anchor,
   );
   ```

### Step 3: Update Both Files

Update `_addMarkerVisual()` in:
- `lib/screens/upload_anchor_screen.dart` (line ~368)
- `lib/screens/navigation_screen.dart` (line ~716)

### Step 4: Test

1. **Upload Anchor Screen:**
   - Tap to place marker → Red sphere should appear
   - Move device → Sphere should stay in place
   - Place multiple markers → Multiple spheres visible

2. **Navigation Screen:**
   - Load map → Resolved anchors show red spheres
   - Move device → Spheres persist in 3D space
   - Select destination → Arrow guides to sphere

## Expected Result

- ✅ Red spheres (15cm diameter) appear at marker positions
- ✅ Spheres persist when user moves around
- ✅ Multiple spheres can be placed
- ✅ Spheres are clearly visible in AR camera view
- ✅ Spheres are removed when markers are cleared

## Troubleshooting

If spheres don't appear:

1. **Check Console Logs:**
   - Look for "🔵 Adding red sphere visual" messages
   - Check for API errors

2. **Verify API:**
   - Confirm `ARObjectManager` method names
   - Check parameter types match

3. **Test Position:**
   - Verify `position` values are correct
   - Check anchor is properly attached

## Files Modified

- ✅ `lib/screens/upload_anchor_screen.dart`
- ✅ `lib/screens/navigation_screen.dart`

## Next Steps

1. Check `ar_flutter_plugin` documentation for correct API
2. Update `_addMarkerVisual()` methods with correct implementation
3. Test on device
4. Adjust sphere size/color as needed














