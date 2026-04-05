bl_info = {
    "name": "Macro: Import FBX",
    "blender": (2, 83, 0),
    "category": "Object",
}

import bpy
import os
from pathlib import Path
from bpy.types import Operator
from bpy.utils import register_class, unregister_class

importDir = 'C:/ImportDir'

def doImport(fp):
    bpy.ops.import_scene.fbx(filepath = fp)

class FBX_ImportLast(Operator):
    bl_idname = "easy_fbx.importlast"
    bl_label = "FBX Import Last"
    bl_options = {'REGISTER', 'UNDO'}
    
    def execute(self, context):
        fileList = sorted(Path(importDir).iterdir(), key=os.path.getmtime, reverse = True)
        
        for f in fileList:
            if f.name.endswith(".fbx"):
                doImport(importDir + "/" + f.name)
                return {'FINISHED'}
        
        return {'CANCELLED'}
    
class FBX_MultiImport(Operator):
    bl_idname = "easy_fbx.multiimport"
    bl_label = "FBX Import Multi"
    bl_options = {'REGISTER', 'UNDO'}
    
    fileCount: bpy.props.IntProperty(name = "Amount")
    fileOffset: bpy.props.IntProperty(name = "Offset")

    def execute(self, context):
        self.report(
        {'INFO'}, '%d %d' % (self.fileCount, self.fileOffset)
        )
        
        fileList = sorted(Path(importDir).iterdir(), key=os.path.getmtime, reverse = True)
        i = 0
        
        for f in fileList:
            if f.name.endswith(".fbx"):
                if i >= self.fileOffset and (i < self.fileCount + self.fileOffset):
                    doImport(importDir + "/" + f.name)
                    
                i=i+1
                
        return {'FINISHED'}
    
class FBX_IDImport(Operator):
    bl_idname = "easy_fbx.importid"
    bl_label = "FBX Import ID"
    bl_options = {'REGISTER', 'UNDO'}
    
    fileID: bpy.props.IntProperty(name = "ID")

    def execute(self, context):
        self.report
        (
        {'INFO'}, '%d' % (self.fileID)
        )
        
        fileList = sorted(Path(importDir).iterdir(), key=os.path.getmtime, reverse = True)
        i = 0
        
        for f in fileList:
            if f.name.endswith(".fbx"):
                if i != self.fileID:
                    doImport(importDir + "/" + f.name)
                    return {'FINISHED'}
                i=i+1
                
        return {'CANCELLED'}
    
class FBX_NPanel(bpy.types.Panel):
    bl_idname = "easy_fbx.npanel"
    bl_label = 'Easy FBX'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'EasyFBX'

    def draw(self, context):
        layout = self.layout
        layout.operator('easy_fbx.importlast', text='Import last')
        layout.operator('easy_fbx.multiimport', text='Import multiple')
        layout.operator('easy_fbx.importid', text='Import by ID')

def register():
    register_class(FBX_ImportLast)
    register_class(FBX_MultiImport)
    register_class(FBX_IDImport)
    register_class(FBX_NPanel)
    
def unregister():
    unregister_class(FBX_ImportLast)
    unregister_class(FBX_MultiImport)
    unregister_class(FBX_IDImport)
    unregister_class(FBX_NPanel)
    
if __name__ == '__main__':
    register()
