---
inclusion: always
---

# Release / DMG version-bump checklist

So **Check for Updates** works, follow this order when cutting a GitHub release
(`vX.Y.Z`) or shipping `DeskPet.dmg`:

1. **Bump the version first** in `Support/Info.plist`:
   - `CFBundleShortVersionString` → `X.Y.Z`
   - `CFBundleVersion` → next integer
2. Update `Tests/DeskPetTests/BundleSmokeTests.swift` to expect the new short
   version.
3. Commit + push the bump **before** building the DMG.
4. Build: `make test && make dist`
5. Verify the built bundle:
   ```bash
   plutil -p DeskPet.app/Contents/Info.plist | grep -E 'CFBundleShortVersionString|CFBundleVersion'
   ```
6. Tag the **bump commit** (not an older feature commit):
   ```bash
   git tag -f vX.Y.Z
   git push --force origin vX.Y.Z
   ```
7. Upload: `gh release upload vX.Y.Z DeskPet.dmg --clobber` (or `gh release
   create` with the DMG).

## Never

- Tag or upload a DMG while `Info.plist` still has the previous version — Check
  for Updates fails with **"The downloaded app is not newer"** (hit on v1.0.2
  and v1.0.3).
- Point `vX.Y.Z` at a commit that lacks the matching plist bump.
