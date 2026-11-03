# Gorm application lab

The selected source is [gnustep/apps-gorm](https://github.com/gnustep/apps-gorm) at `5fd8b86696574ba13c8f9e2340755bb3200b15d1`. The checkout's README and CI include Linux GNUstep builds using Clang and the gnustep-2.0 runtime. This is evidence of an intended build path, not a fresh successful run of this lab. Native Windows debugging is not yet validated.

Gorm requires **tools-make, libobjc2, gnustep-base, gnustep-gui and gnustep-back**. The existing repository's `build-all` builds the base stack, not the graphical stack. Install gui/back against that same libobjc2 stack before this lab; do not substitute distribution GUI binaries using GCC's separate runtime. Use Gorm's pinned README/CI for the GUI dependencies and keep their revisions in the validation report.

After the Linux lesson setup:

```bash
python3 lessons/gorm.py setup --config "$HOME/code/lesson-output/config.json"
python3 lessons/gorm.py smoke --config "$HOME/code/lesson-output/config.json"
code "$HOME/code/lesson-output/gorm.code-workspace"
```

The setup clones the pinned revision in the lab output directory, builds debug objects and installs Gorm into GNUstep's **USER** installation domain. Installation is necessary for GormCore and palettes; it does not install into the system domain. Use a dedicated lab account if you already have another user-installed Gorm. An existing source checkout is checked for the exact revision and local changes before it is built.

The generated `gorm.launch.json` is a copyable launch configuration for a clone; `gorm.code-workspace` opens the clone directly with the same settings. The startup smoke test checks `-[GormAppDelegate applicationDidFinishLaunching:]` without requiring a menu click. Without DISPLAY it uses `xvfb-run` if installed.

For the recorded interactive lab, select “Gorm: new document”, start the application, then choose **Document → New** (or the New command exposed by the current GNUstep menu style). The breakpoint targets `-[GormDocumentController newDocument:]` in `GormCore/GormDocumentController.m`. Inspect `self`, show the caller, then continue to the new-document UI. Verify the exact menu label during rehearsal; different interface styles can arrange menus differently.

The authoring machine's WSL service began failing with `Wsl/Service/0x8007274c` during preparation. The pinned repository and breakpoint source were inspected, but this build and graphical run remain pending. Do not label the workflow PASS until the smoke test produces the expected source stop.

Gorm's source carries its own licensing, including GPL notices. Clone the upstream repository with its notices intact. The lesson links to it rather than repackaging its source as lesson-owned code. ObjFW, mentioned in the RFC as outside this runtime's scope, is not being silently added to the compatibility claims.
