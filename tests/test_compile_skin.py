"""Synthetic-only compiler fixtures; no player layouts or artwork are stored."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("compile_skin", Path(__file__).parents[1] / "tools/compile_skin.py")
compiler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compiler)


class CompileSkinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "uifiles/default"
        self.skin = self.root / "uifiles/Test-stock"
        self.base.mkdir(parents=True)
        self.skin.mkdir()
        self.write(self.base, "EQUI.xml", '<XML><Composite><Include>Core.xml</Include></Composite></XML>')
        self.write(self.base, "Core.xml", '<XML><Screen item="Base"><Text>Base</Text></Screen></XML>')
        self.write(self.skin, "EQUI.xml", '<XML><Composite><Include>Custom.xml</Include></Composite></XML>')
        self.write(self.skin, "Custom.xml", '<XML><Screen item="Custom"><Text>Custom</Text></Screen></XML>')

    @staticmethod
    def write(root, name, value):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding="utf-8")

    def compile(self, **kw):
        return compiler.compile_skin(self.root, "test-STOCK", include_plans=True, **kw)

    @staticmethod
    def window(result, name):
        return compiler.lua_literal(result["plans"][name])

    def test_selected_fallback_completion_and_custom_unreferenced(self):
        self.write(self.skin, "CORE.XML", '<XML><Screen item="Base"><Text>Selected</Text></Screen></XML>')
        self.write(self.skin, "Extra.xml", '<XML><Screen item="Extra"><Text>Extra</Text></Screen></XML>')
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        result = self.compile()
        self.assertEqual(result["report"]["screen_count"], 3)
        self.assertIn('["text"]="Selected"', self.window(result, "Base"))
        self.assertIn('uifiles', str(self.base))
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()})
        self.assertFalse(any(name.endswith(".xml") for name in result["files"]))
        self.assertFalse(any(str(self.root).encode() in data for data in result["files"].values()))

    def test_control_order_anchors_schema_defaults_and_identifier_data(self):
        self.write(self.skin, "Custom.xml", '''<XML><Schema>
          <ElementType name="Control"><element name="Font" type="int"><default>7</default></element></ElementType>
          <ElementType name="Button"><superType type="Control"/><element name="Text" type="string"/></ElementType>
          </Schema><Button item="B"><ScreenID>Click</ScreenID><Text>001</Text><Location><X>-4</X><Y>8</Y></Location>
          <Size><CX>20</CX><CY>9</CY></Size><RightAnchorToLeft>false</RightAnchorToLeft><RightAnchorOffset>3</RightAnchorOffset></Button>
          <Gauge item="G"><EQType>42</EQType></Gauge><InvSlot item="S"><EQType>inventory/Equip 0</EQType></InvSlot>
          <Screen item="Custom"><Pieces>Button:B</Pieces><Pieces>G</Pieces><ScreenPieces>S</ScreenPieces></Screen></XML>''')
        text = self.window(self.compile(), "Custom")
        self.assertLess(text.index('["item"]="B"'), text.index('["item"]="G"'))
        self.assertLess(text.index('["item"]="G"'), text.index('["item"]="S"'))
        self.assertIn('["font"]=7', text)
        self.assertIn('["text"]="001"', text)
        self.assertIn('["rightToLeft"]=false', text)
        self.assertIn('["slot"]="inventory/Equip 0"', text)
        self.assertIn('["gaugeEqType"]=42', text)

    def test_frames_templates_image_resolution_and_missing_diagnostic(self):
        png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 64, 32)
        (self.skin / "Art.PNG").write_bytes(png)
        self.write(self.skin, "Custom.xml", '''<XML><TextureInfo item="art.png"><Size><CX>64</CX><CY>32</CY></Size></TextureInfo>
          <Ui2DAnimation item="A"><Cycle>true</Cycle><Frames><Texture>art.png</Texture><Location><X>4</X><Y>8</Y></Location>
          <Size><CX>16</CX><CY>12</CY></Size><Duration>75</Duration></Frames><Frames><Texture>absent.tga</Texture></Frames></Ui2DAnimation>
          <ButtonDrawTemplate item="T"><Normal>A</Normal><Pressed>A</Pressed></ButtonDrawTemplate>
          <Screen item="Custom"><Text>Custom</Text></Screen></XML>''')
        result = self.compile()
        text = result["files"]["lib/compiled/index.lua"].decode()
        self.assertIn('uifiles/Test-stock/Art.PNG', text)
        self.assertIn('["duration"]=75', text)
        self.assertIn('["cycle"]=true', text)
        self.assertIn('["type"]="ButtonDrawTemplate"', text)
        self.assertEqual([d["name"] for d in result["report"]["diagnostics"] if d["kind"] == "missing_texture"], ["absent.tga"])

    def test_reviewed_asset_map_requires_exact_hash_and_safe_target(self):
        path = self.root / "repair.tga"
        path.write_bytes(bytes([0, 0, 2]) + bytes(9) + struct.pack("<HH", 8, 8) + bytes(2))
        self.write(self.skin, "Custom.xml", '<XML><TextureInfo item="missing.tga"/><Screen item="Custom"><Text>C</Text></Screen></XML>')
        row = {"skin": "Test-stock", "target": "missing.tga", "file": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        result = self.compile(asset_map={"schema": 1, "assets": [row]})
        self.assertIn('["repair"]=true', result["files"]["lib/compiled/index.lua"].decode())
        row["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.compile(asset_map={"schema": 1, "assets": [row]})

    def test_rejects_dtd_traversal_and_reference_cycles(self):
        for content, message in [
            ('<!DOCTYPE XML [<!ENTITY x "expanded">]><XML>&x;</XML>', "DTD"),
            ('<XML><Include>../outside.xml</Include></XML>', "unsafe"),
            ('<XML><Include>EQUI.xml</Include></XML>', "cycle"),
            ('<XML><Screen item="Custom"><Pieces>Custom</Pieces></Screen></XML>', "cycle"),
        ]:
            with self.subTest(message=message):
                self.write(self.skin, "Custom.xml", content)
                with self.assertRaisesRegex(ValueError, message):
                    self.compile()
        with self.assertRaisesRegex(ValueError, "safe UI folder"):
            compiler.compile_skin(self.root, "../default")

    def test_literals_are_data_only_deterministic_and_escape_controls(self):
        text = '\\"; os.execute("unexpected"); --\n\x01' + '9'
        escaped = compiler.lua_literal(text)
        self.assertTrue(escaped.startswith('"') and escaped.endswith('"'))
        self.assertIn('\\010\\0019', escaped)
        self.assertEqual(self.compile()["files"], self.compile()["files"])
        with self.assertRaises(ValueError):
            compiler.lua_literal(float("nan"))

    def test_singleton_duplicates_do_not_turn_geometry_into_arrays(self):
        self.write(self.skin, "Custom.xml", '''<XML><Button item="B"><Location><X>1</X></Location>
          <Location><X>9</X><Y>4</Y></Location><Size><CX>8</CX></Size><Size><CX>18</CX><CY>6</CY></Size></Button>
          <Screen item="Custom"><Pieces>B</Pieces><Pieces>B</Pieces></Screen></XML>''')
        result = self.compile()
        text = self.window(result, "Custom")
        self.assertIn('["x"]=9', text)
        self.assertIn('["w"]=18', text)
        self.assertEqual(text.count('["item"]="B"'), 2)
        self.assertTrue(any(d["kind"] == "duplicate_property" for d in result["report"]["diagnostics"]))

    def test_unreferenced_backup_cannot_override_active_definition(self):
        self.write(self.skin, "ZBackup.xml", '<XML><Screen item="Custom"><Text>Backup</Text></Screen><Screen item="Extra"/></XML>')
        result = self.compile()
        self.assertIn('["text"]="Custom"', self.window(result, "Custom"))
        self.assertNotIn('["text"]="Backup"', self.window(result, "Custom"))
        self.assertEqual(result["report"]["screen_count"], 3)

    def test_source_style_art_font_palette_and_explicit_anchor_flags(self):
        self.write(self.skin, "Custom.xml", '''<XML>
          <WindowDrawTemplate item="Frame"><Border><TopLeft>A</TopLeft><Middle>B</Middle></Border></WindowDrawTemplate>
          <ButtonDrawTemplate item="ButtonArt"><Normal>A</Normal><Flyby>B</Flyby></ButtonDrawTemplate>
          <Button item="B"><Font>2</Font><Text>Apply</Text><Template>ButtonArt</Template></Button>
          <Gauge item="HP"><EQType>1</EQType><FillTint><R>128</R><G>64</G><B>0</B></FillTint>
          <GaugeDrawTemplate><Fill>A</Fill><Background>B</Background></GaugeDrawTemplate></Gauge>
          <Screen item="Custom"><DrawTemplate>Frame</DrawTemplate><TopAnchorOffset>0</TopAnchorOffset>
          <Pieces>B</Pieces><Pieces>HP</Pieces></Screen></XML>''')
        result = self.compile()
        style = result["report"]["style"]
        self.assertEqual(style["frame"]["template"], "Frame")
        self.assertEqual(style["button"]["template"], "ButtonArt")
        self.assertTrue(style["gauge"]["template"].startswith("@style/GaugeDrawTemplate/"))
        self.assertEqual(style["fonts"]["button"], 2)
        self.assertEqual(style["palette"]["hp"], [128 / 255, 64 / 255, 0, 1])
        text = self.window(result, "Custom")
        self.assertIn('["explicit"]={["bottom"]=false,["left"]=false,["right"]=false,["top"]=true}', text)

    def test_sparse_schema_defaults_preserve_normalized_values_and_share_copied_layout(self):
        schema = '''<Schema><ElementType name="Button"><element name="Font" type="int"><default>7</default></element>
          <element name="Style_Transparent" type="boolean"><default>false</default></element></ElementType></Schema>'''
        self.write(self.base, "Core.xml", '<XML>' + schema + '<Button item="B"/><Screen item="Base"><Pieces>B</Pieces></Screen></XML>')
        default = compiler.compile_skin(self.root, "default", include_plans=True)
        self.write(self.skin, "CORE.XML", (self.base / "Core.xml").read_text())
        selected = self.compile()
        self.assertEqual(self.window(default, "Base"), self.window(selected, "Base"))
        text = self.window(selected, "Base")
        self.assertIn('["font"]=7', text)
        self.assertNotIn('["Font"]=7', text)
        self.assertIn('["Font"]=7', selected["files"]["lib/compiled/index.lua"].decode())

    def test_tuple_contract_preserves_unknown_fields_slots_and_anchor_mask(self):
        self.write(self.skin, "Custom.xml", '''<XML><InvSlot item="S"><ScreenID>VisibleSlot</ScreenID>
          <Location><X>11</X><Y>13</Y></Location><Size><CX>17</CX><CY>19</CY></Size>
          <TopAnchorOffset>3</TopAnchorOffset><RightAnchorOffset>5</RightAnchorOffset>
          <EQType>inventory/Equip 2</EQType><UnknownSetting>verbatim</UnknownSetting></InvSlot>
          <Screen item="Custom"><Pieces>S</Pieces></Screen></XML>''')
        result = self.compile()
        self.assertEqual(result["index"]["encoding"], "node-tuples-v1")
        packed = compiler.pack_node(result["plans"]["Custom"])[12][0]
        self.assertEqual(packed[:3], ["InvSlot", "S", "VisibleSlot"])
        self.assertEqual(packed[4], [11, 13, 17, 19])
        self.assertEqual(packed[5][-1], 9)
        self.assertEqual(packed[11]["UnknownSetting"], "verbatim")
        self.assertEqual(packed[13], "inventory/Equip 2")
        self.assertIsNone(packed[14])

    def test_tga_palette_uses_opaque_cropped_pixels_and_decodes_rle(self):
        path = self.skin / "sample.tga"
        header = bytes([0, 0, 2]) + bytes(9) + struct.pack("<HH", 2, 1) + bytes([32, 40])
        path.write_bytes(header + bytes([0, 255, 0, 0, 30, 20, 10, 255]))
        self.assertEqual(compiler.sample_image_rgba(path), [10 / 255, 20 / 255, 30 / 255, 1])
        self.assertEqual(compiler.sample_image_rgba(path, {"x": 1, "y": 0, "w": 1, "h": 1}), [10 / 255, 20 / 255, 30 / 255, 1])
        header = bytearray(header); header[2] = 10
        path.write_bytes(header + bytes([129, 60, 50, 40, 255]))
        self.assertEqual(compiler.sample_image_rgba(path), [40 / 255, 50 / 255, 60 / 255, 1])

    def test_outer_frame_beats_nested_layout_and_bad_numeric_is_diagnosed(self):
        self.write(self.skin, "Custom.xml", '''<XML><Schema><ElementType name="RGB"><element name="R" type="int"/></ElementType>
          <ElementType name="Label"><element name="TextColor" type="RGB"/></ElementType></Schema>
          <WindowDrawTemplate item="Outer"/><WindowDrawTemplate item="Inner"/>
          <Label item="L"><TextColor><R>255B</R></TextColor></Label>
          <Screen item="Nested"><DrawTemplate>Inner</DrawTemplate><Pieces>L</Pieces></Screen>
          <Screen item="InventoryWindow"><DrawTemplate>Outer</DrawTemplate><Pieces>Nested</Pieces></Screen></XML>''')
        result = self.compile()
        self.assertEqual(result["report"]["style"]["frame"]["template"], "Outer")
        self.assertTrue(any(d["kind"] == "invalid_numeric" for d in result["report"]["diagnostics"]))
        self.assertEqual(result["plans"]["InventoryWindow"]["children"][0]["children"][0]["colors"]["TextColor"]["r"], 255)

    def test_malformed_boolean_prefix_and_numeric_boolean_forms(self):
        self.write(self.skin, "Custom.xml", '''<XML><Schema><ElementType name="Screen">
          <element name="TopAnchorToTop" type="boolean"/><element name="BottomAnchorToTop" type="boolean"/>
          </ElementType></Schema><Screen item="Custom"><TopAnchorToTop>0</TopAnchorToTop>
          <BottomAnchorToTop>false&gt;</BottomAnchorToTop></Screen></XML>''')
        result = self.compile()
        self.assertIs(result["plans"]["Custom"]["anchors"]["topToTop"], False)
        self.assertIs(result["plans"]["Custom"]["anchors"]["bottomToTop"], False)
        self.assertEqual([d["kind"] for d in result["report"]["diagnostics"]].count("invalid_boolean"), 1)

    def test_cli_cannot_write_elsewhere_in_game_directory(self):
        target = self.root / "generated-outside-uifiles"
        completed = subprocess.run([sys.executable, str(Path(compiler.__file__)), "--game-dir", str(self.root),
                                    "--skin", "Test-stock", "--output", str(target)],
                                   capture_output=True, text=True)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("outside game sources", completed.stderr)
        self.assertFalse(target.exists())

    def test_generic_button_style_ignores_frequent_icon_and_grid_templates(self):
        self.write(self.skin, "Custom.xml", '''<XML>
          <Ui2DAnimation item="Atlas"><Grid>true</Grid></Ui2DAnimation>
          <ButtonDrawTemplate item="BDT_DragItem"><NormalDecal>Atlas</NormalDecal></ButtonDrawTemplate>
          <ButtonDrawTemplate item="LooksOrdinary"><NormalDecal>Atlas</NormalDecal></ButtonDrawTemplate>
          <ButtonDrawTemplate item="20_HotButton"><Normal>Other</Normal></ButtonDrawTemplate>
          <ButtonDrawTemplate item="BDT_Normal"><Normal>Plain</Normal></ButtonDrawTemplate>
          <Button item="Icon1"><Text>One</Text><Template>BDT_DragItem</Template></Button>
          <Button item="Icon2"><Text>Two</Text><Template>LooksOrdinary</Template></Button>
          <Button item="Icon3"><Text>Three</Text><Template>LooksOrdinary</Template></Button>
          <Button item="Hot"><Text>Hot</Text><Template>20_HotButton</Template></Button>
          <Button item="Done"><Text>Done</Text><Template>BDT_Normal</Template></Button>
          <Screen item="Custom"><Pieces>Icon1</Pieces><Pieces>Icon2</Pieces><Pieces>Icon3</Pieces><Pieces>Hot</Pieces><Pieces>Done</Pieces></Screen>
          </XML>''')
        result = self.compile()
        self.assertEqual(result["report"]["style"]["button"]["template"], "BDT_Normal")
        self.assertEqual(result["plans"]["Custom"]["children"][0]["art"]["template"], "BDT_DragItem")
        self.assertEqual(result["index"]["templates"]["LooksOrdinary"]["fields"]["NormalDecal"], "Atlas")


if __name__ == "__main__":
    unittest.main()
