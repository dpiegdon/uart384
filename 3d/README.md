
Tested with FreeCAD 1.0.2 and Blender 4.5.2 LTS:

FreeCAD workflow
================

Direct export of 3d STEP file
-----------------------------

In KiCad PCB Editor: File -> Export -> Step, then enable everything on the left:

- Board body
- cut vias in board body
- export silkscreen
- export solder mask
- export *all* components
- export tracks and vias
- export pads
- export zones
- export inner conductor layers
- fuse shapes
- fill all vias
- optionally on the right: ignore DNP components
- Export, saving as STEP file

In FreeCAD: import STEP file via File -> Import.

=> Now create enclosure (or whatever else) in CAD.


Old version
-----------

NOTE: this does not work well when exporting to blender at a later stage. Better use the direct 3d export above.

In KiCad PCB Editor:

- Plot silkscreen layers to DXF format:
  - File -> Plot
  - Set Plot format to DXF,
  - Select Silkscreen layers (don't care about others)
  - Plot

In FreeCAD: Use KiCadStepUp bench to:
- load board
- add tracks
- add silkscreen (exported DXF file)


Blender workflow
================

Export Enclosure and PCB
------------------------

In FreeCAD: select PCB and enclosure bodies, then: File -> Export, then export as glTF.

Import in Blender
-----------------

Import glTF file via: File -> Import.

Knock yourself out!
