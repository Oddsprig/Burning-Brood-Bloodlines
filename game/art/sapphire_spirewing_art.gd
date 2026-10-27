class_name SapphireSpirewingArt
extends RefCounted
## Code-drawn 2.5D normal-mapped wyvern art for all 16 dragon gem colours and 6 breeds.
## Six 128x96 wingbeat frames per variant, painted in memory; no imported bitmap or RNG.
const SIZE := Vector2i(128, 96)
const FRAME_COUNT := 6
const OUTLINE := Color("0a1028")
const SKIN := [Color("13214f"), Color("1c3480"), Color("2850b0"), Color("3a72d4"), Color("5d97ea"), Color("a2cdf7")]
const SKIN_FAR := [Color("0e1838"), Color("142659"), Color("1c3a80"), Color("2a56a8"), Color("3f72c4"), Color("6d9ad8")]
const BELLY := [Color("3d5d96"), Color("6d93c8"), Color("a4c6ea"), Color("d8ecff")]
const BELLY_FAR := [Color("2c4674"), Color("4f72a6"), Color("7a9ccc"), Color("a8c4e4")]
const MEMBRANE := [Color("161a44"), Color("232a68"), Color("323f92"), Color("4558b4"), Color("6a80d4")]
const MEMBRANE_FAR := [Color("0f1232"), Color("181d4c"), Color("222c6a"), Color("30408c"), Color("4a5ca8")]
const GEM := [Color("0b1660"), Color("1838b8"), Color("3274f0"), Color("8cc8ff"), Color.WHITE]

const MORPHS := ["spirewing", "broadmantle", "reedrunner", "ironcrest", "stormkeel", "duskfin"]
const PALETTES := {
	"ruby": {
		"outline": Color("24060e"),
		"skin": [Color("3b0a18"), Color("631126"), Color("8f1836"), Color("bd2448"), Color("e04868"), Color("ff8ca3")],
		"skin_far": [Color("280710"), Color("440c1b"), Color("631227"), Color("871b36"), Color("a8324e"), Color("cf637b")],
		"belly": [Color("7a3b48"), Color("a8606c"), Color("d4969e"), Color("f7d4d8")],
		"belly_far": [Color("572833"), Color("7a434e"), Color("9e6872"), Color("c498a0")],
		"membrane": [Color("2e0818"), Color("4a0e26"), Color("6e1838"), Color("96264c"), Color("c94a70")],
		"membrane_far": [Color("1f0510"), Color("33091a"), Color("4d1027"), Color("6b1b38"), Color("913554")],
		"gem": [Color("4a0618"), Color("9e1438"), Color("e62255"), Color("ff7898"), Color("ffebf0")],
		"eye": [Color("ffd15c"), Color("fff7d6")],
		"tooth": Color("ffe6ec")
	},
	"sapphire": {
		"outline": OUTLINE,
		"skin": SKIN,
		"skin_far": SKIN_FAR,
		"belly": BELLY,
		"belly_far": BELLY_FAR,
		"membrane": MEMBRANE,
		"membrane_far": MEMBRANE_FAR,
		"gem": GEM,
		"eye": [Color("8ff6ff"), Color("e8ffff")],
		"tooth": Color("e4f2ff")
	},
	"black_diamond": {
		"outline": Color("07070e"),
		"skin": [Color("10111c"), Color("1a1c2e"), Color("272b42"), Color("3a405e"), Color("586084"), Color("98a2c4")],
		"skin_far": [Color("0b0c14"), Color("131522"), Color("1d2032"), Color("2b2f47"), Color("414766"), Color("6e7699")],
		"belly": [Color("2d3145"), Color("4c526e"), Color("78809e"), Color("b8c0dc")],
		"belly_far": [Color("202333"), Color("363b52"), Color("565d78"), Color("858da8")],
		"membrane": [Color("0d0e18"), Color("171929"), Color("24283e"), Color("363c59"), Color("586186")],
		"membrane_far": [Color("080910"), Color("10121d"), Color("191c2c"), Color("262b40"), Color("3e4461")],
		"gem": [Color("181b2e"), Color("383f63"), Color("6873a1"), Color("b2bcdb"), Color("f0f4ff")],
		"eye": [Color("9ee6ff"), Color("f2fcff")],
		"tooth": Color("dce2f5")
	},
	"emerald": {
		"outline": Color("061f14"),
		"skin": [Color("0c3624"), Color("13543a"), Color("1b7853"), Color("289e6e"), Color("4ac48e"), Color("9ce8be")],
		"skin_far": [Color("08261a"), Color("0e3d2a"), Color("14573d"), Color("1f7553"), Color("36946b"), Color("6ec298")],
		"belly": [Color("3b755c"), Color("64a183"), Color("99cfb0"), Color("d4f5df")],
		"belly_far": [Color("295441"), Color("47755f"), Color("6e9e84"), Color("9ec7b0")],
		"membrane": [Color("0a2b20"), Color("124534"), Color("1c634b"), Color("2b8566"), Color("50b38e")],
		"membrane_far": [Color("071f17"), Color("0d3024"), Color("144736"), Color("1f614a"), Color("398569")],
		"gem": [Color("073b26"), Color("128054"), Color("26c480"), Color("8cf2be"), Color("ebfff4")],
		"eye": [Color("ffe066"), Color("fff9d6")],
		"tooth": Color("e2faec")
	},
	"amethyst": {
		"outline": Color("180b26"),
		"skin": [Color("2b1542"), Color("462369"), Color("653594"), Color("874ec0"), Color("ad76e3"), Color("debaff")],
		"skin_far": [Color("1f0f30"), Color("32194d"), Color("49266e"), Color("63388f"), Color("8154b0"), Color("ab82d4")],
		"belly": [Color("5e4678"), Color("896ca8"), Color("b79cd4"), Color("e8d6fa")],
		"belly_far": [Color("433157"), Color("634d7a"), Color("8870a1"), Color("b39cc9")],
		"membrane": [Color("231038"), Color("381b59"), Color("52297d"), Color("703ca3"), Color("9d66cf")],
		"membrane_far": [Color("170a26"), Color("27123e"), Color("3a1c59"), Color("502a78"), Color("72479c")],
		"gem": [Color("311154"), Color("6628a8"), Color("9e4df0"), Color("deb3ff"), Color("faf0ff")],
		"eye": [Color("ffdf78"), Color("fff8de")],
		"tooth": Color("f2e6ff")
	},
	"opal": {
		"outline": Color("1a292b"),
		"skin": [Color("4f6668"), Color("6e8a8c"), Color("91adad"), Color("b4ccc9"), Color("d2e3df"), Color("f0faf7")],
		"skin_far": [Color("3b4d4f"), Color("53696b"), Color("6f8787"), Color("8da3a1"), Color("acc2bf"), Color("cce0dc")],
		"belly": [Color("7a9491"), Color("a3bfba"), Color("cae0dc"), Color("f2fcf9")],
		"belly_far": [Color("5b706e"), Color("7c9490"), Color("9fb8b3"), Color("c5dbd6")],
		"membrane": [Color("3d595e"), Color("567b82"), Color("749ea6"), Color("96c2ca"), Color("bfe5eb")],
		"membrane_far": [Color("2c4145"), Color("3f5b61"), Color("567980"), Color("71989f"), Color("95bbc2")],
		"gem": [Color("2e666e"), Color("4f9da8"), Color("7bd1db"), Color("c2f5fa"), Color("ffffff")],
		"eye": [Color("5ef0ff"), Color("ebffff")],
		"tooth": Color("f0fcfb")
	},
	"topaz": {
		"outline": Color("261304"),
		"skin": [Color("4a2608"), Color("753e10"), Color("a35b1c"), Color("cf7c2e"), Color("eda455"), Color("ffd999")],
		"skin_far": [Color("361b05"), Color("542c0b"), Color("784214"), Color("995a22"), Color("b8773b"), Color("d9a36c")],
		"belly": [Color("8a5e32"), Color("b88752"), Color("e0b67e"), Color("fce5be")],
		"belly_far": [Color("634322"), Color("87613a"), Color("ab8459"), Color("cfa97e")],
		"membrane": [Color("3d1d06"), Color("612f0d"), Color("8a4516"), Color("b56024"), Color("de8a4b")],
		"membrane_far": [Color("2b1404"), Color("452108"), Color("63310f"), Color("85451a"), Color("a86334")],
		"gem": [Color("592c06"), Color("a85911"), Color("eb8c26"), Color("ffd275"), Color("fff8e6")],
		"eye": [Color("82f2ff"), Color("e8ffff")],
		"tooth": Color("fff2d6")
	},
	"garnet": {
		"outline": Color("1c060c"),
		"skin": [Color("2e0b16"), Color("4a1324"), Color("6b1e35"), Color("8f2d47"), Color("b84c5e"), Color("e68a7c")],
		"skin_far": [Color("210710"), Color("360d1a"), Color("4f1527"), Color("6b2135"), Color("8c3847"), Color("b36260")],
		"belly": [Color("69353c"), Color("945458"), Color("bf817e"), Color("ebc0b7")],
		"belly_far": [Color("4a2429"), Color("6b3b3e"), Color("8f5c5b"), Color("b58682")],
		"membrane": [Color("260812"), Color("3d0f1e"), Color("59182c"), Color("7a263c"), Color("a84456")],
		"membrane_far": [Color("1a050c"), Color("2b0a15"), Color("40101f"), Color("591b2b"), Color("7d313f")],
		"gem": [Color("3d0a1a"), Color("781932"), Color("b83248"), Color("e8826b"), Color("ffebe3")],
		"eye": [Color("ffbe4f"), Color("fff3d1")],
		"tooth": Color("fae3dc")
	},
	"jade": {
		"outline": Color("102119"),
		"skin": [Color("223d31"), Color("355c4b"), Color("4b7d67"), Color("669e84"), Color("8ec2a3"), Color("c9e6c8")],
		"skin_far": [Color("182b23"), Color("264236"), Color("375c4b"), Color("4b7863"), Color("68967c"), Color("96bd9e")],
		"belly": [Color("547561"), Color("7b9e84"), Color("a8c9ab"), Color("dcf0d8")],
		"belly_far": [Color("3c5446"), Color("597561"), Color("7b9980"), Color("a3bfa3")],
		"membrane": [Color("1c3329"), Color("2c4f40"), Color("406e5a"), Color("588f75"), Color("80b899")],
		"membrane_far": [Color("13241c"), Color("1f382d"), Color("2e4f40"), Color("406955"), Color("5e8a72")],
		"gem": [Color("1f4232"), Color("3d785c"), Color("68ad86"), Color("bce0b4"), Color("f4ffef")],
		"eye": [Color("ffd86b"), Color("fff8db")],
		"tooth": Color("eaf7e6")
	},
	"aquamarine": {
		"outline": Color("082226"),
		"skin": [Color("144047"), Color("21636b"), Color("338991"), Color("4ab0b8"), Color("74d4d9"), Color("c4f7f2")],
		"skin_far": [Color("0e2e33"), Color("17484f"), Color("24646b"), Color("36848a"), Color("54a3a8"), Color("8ccfd1")],
		"belly": [Color("47858a"), Color("6faeb0"), Color("a0d6d4"), Color("dafaf5")],
		"belly_far": [Color("336166"), Color("508082"), Color("75a3a3"), Color("a2ccc9")],
		"membrane": [Color("10363b"), Color("1b545c"), Color("297580"), Color("3d99a3"), Color("68c4cc")],
		"membrane_far": [Color("0b2529"), Color("133b40"), Color("1d545c"), Color("2c7078"), Color("4b949c")],
		"gem": [Color("0e4a52"), Color("228994"), Color("45c9d1"), Color("a8f5ed"), Color("f2fffe")],
		"eye": [Color("ffe478"), Color("fffbe0")],
		"tooth": Color("e6fcf9")
	},
	"citrine": {
		"outline": Color("261d04"),
		"skin": [Color("4d3b08"), Color("785c0f"), Color("a68119"), Color("d1a72a"), Color("f0cb54"), Color("fff09e")],
		"skin_far": [Color("362905"), Color("54410a"), Color("755b12"), Color("96771e"), Color("b5963a"), Color("d9c06c")],
		"belly": [Color("8c7530"), Color("b89e4f"), Color("e0ca7e"), Color("fcf0be")],
		"belly_far": [Color("635321"), Color("857138"), Color("a89458"), Color("cfc082")],
		"membrane": [Color("3d2f06"), Color("614b0c"), Color("8a6b15"), Color("b58f24"), Color("deb84b")],
		"membrane_far": [Color("2b2004"), Color("453408"), Color("634c0e"), Color("856719"), Color("a88934")],
		"gem": [Color("594306"), Color("a88211"), Color("ebc026"), Color("ffea85"), Color("fffce8")],
		"eye": [Color("78ebff"), Color("e8fcff")],
		"tooth": Color("fff9d6")
	},
	"moonstone": {
		"outline": Color("191d2b"),
		"skin": [Color("3d445e"), Color("586282"), Color("7783a6"), Color("99a5c7"), Color("c0c8e0"), Color("f5e4d7")],
		"skin_far": [Color("2b3045"), Color("404761"), Color("586180"), Color("737d9c"), Color("929cb8"), Color("bfb8bd")],
		"belly": [Color("6e738c"), Color("989ab0"), Color("c7c2cf"), Color("f7e8dc")],
		"belly_far": [Color("4f5366"), Color("6e7185"), Color("9190a1"), Color("bdb5bd")],
		"membrane": [Color("30364f"), Color("475070"), Color("636e94"), Color("8490b5"), Color("b8b5cf")],
		"membrane_far": [Color("212538"), Color("323952"), Color("47506e"), Color("606a8a"), Color("8688a6")],
		"gem": [Color("444c6e"), Color("7580ab"), Color("aeb8db"), Color("f2d8c9"), Color("fff8f2")],
		"eye": [Color("ffe299"), Color("fff9eb")],
		"tooth": Color("faf0e8")
	},
	"pearl": {
		"outline": Color("2b231b"),
		"skin": [Color("5e4f40"), Color("82705d"), Color("a6927c"), Color("c9b69f"), Color("e6d6c0"), Color("fcf3e4")],
		"skin_far": [Color("45392e"), Color("615244"), Color("7d6c5b"), Color("998875"), Color("b8a793"), Color("d9cbb8")],
		"belly": [Color("8c7b68"), Color("b5a490"), Color("dbccb8"), Color("fcf5eb")],
		"belly_far": [Color("66594b"), Color("877867"), Color("a89987"), Color("cfc2b0")],
		"membrane": [Color("4f4036"), Color("6e5b4e"), Color("91796a"), Color("b59d8d"), Color("dec7b6")],
		"membrane_far": [Color("382d26"), Color("4f4037"), Color("69574b"), Color("857164"), Color("a89385")],
		"gem": [Color("6e5d4b"), Color("a38f78"), Color("d4c2ab"), Color("f7ebd9"), Color("ffffff")],
		"eye": [Color("73e6f5"), Color("ebfcff")],
		"tooth": Color("fffaf2")
	},
	"onyx": {
		"outline": Color("0a090a"),
		"skin": [Color("141314"), Color("211f21"), Color("333032"), Color("4a4547"), Color("6e6564"), Color("b8a390")],
		"skin_far": [Color("0e0d0e"), Color("171617"), Color("242223"), Color("363234"), Color("504949"), Color("827367")],
		"belly": [Color("3d3632"), Color("63574f"), Color("948274"), Color("d2bca6")],
		"belly_far": [Color("2b2623"), Color("473f39"), Color("6b5e54"), Color("998777")],
		"membrane": [Color("121012"), Color("1f1c1e"), Color("302b2d"), Color("473f41"), Color("736460")],
		"membrane_far": [Color("0c0b0c"), Color("151314"), Color("211e1f"), Color("312b2d"), Color("4f4543")],
		"gem": [Color("241f1c"), Color("52463d"), Color("8c7765"), Color("d6bfa8"), Color("faf0e6")],
		"eye": [Color("ff9442"), Color("ffe8cf")],
		"tooth": Color("ebd9c8")
	},
	"diamond": {
		"outline": Color("16222e"),
		"skin": [Color("3e5469"), Color("5a7691"), Color("7c9ab5"), Color("a1bdd6"), Color("c6dced"), Color("f2f9ff")],
		"skin_far": [Color("2d3e4f"), Color("43596e"), Color("5d768c"), Color("7b95ab"), Color("9cb6cc"), Color("c5dbed")],
		"belly": [Color("6d879e"), Color("96b1c7"), Color("c2daed"), Color("f7fcff")],
		"belly_far": [Color("4f6478"), Color("70889c"), Color("95aec2"), Color("bfd6e8")],
		"membrane": [Color("32485c"), Color("4b6985"), Color("698ca8"), Color("8eb2cf"), Color("bfe0fa")],
		"membrane_far": [Color("243442"), Color("364d61"), Color("4d6980"), Color("68879e"), Color("90b0c7")],
		"gem": [Color("43617a"), Color("749bbf"), Color("b0d4f0"), Color("e6f5ff"), Color("ffffff")],
		"eye": [Color("7df2ff"), Color("f5ffff")],
		"tooth": Color("ffffff")
	},
	"tourmaline": {
		"outline": Color("112120"),
		"skin": [Color("1b3635"), Color("295250"), Color("3b706d"), Color("528f8b"), Color("7ab3ad"), Color("d498ad")],
		"skin_far": [Color("132625"), Color("1e3b3a"), Color("2b5250"), Color("3d6b68"), Color("598783"), Color("9c7382")],
		"belly": [Color("6e4a58"), Color("99697b"), Color("c793a6"), Color("f2c9d7")],
		"belly_far": [Color("4f343f"), Color("6e4b59"), Color("916878"), Color("b88fa0")],
		"membrane": [Color("381d29"), Color("572c3f"), Color("7a3f58"), Color("a35876"), Color("d982a3")],
		"membrane_far": [Color("26131c"), Color("3d1f2c"), Color("572d3f"), Color("753f56"), Color("9c5d77")],
		"gem": [Color("4a182b"), Color("8c2d52"), Color("c94f7c"), Color("f29bb8"), Color("ffebf2")],
		"eye": [Color("ffd670"), Color("fff7db")],
		"tooth": Color("fae3ec")
	}
}

const WING_POSES := [
	[Vector2(-3, -14), Vector2(-1, -29), Vector2(-14, -42), Vector2(-33, -37), Vector2(-41, -16)],
	[Vector2(-4, -12), Vector2(-4, -26), Vector2(-22, -41), Vector2(-39, -30), Vector2(-42, -9)],
	[Vector2(-6, -8), Vector2(-10, -15), Vector2(-38, -24), Vector2(-44, -7), Vector2(-36, 4)],
	[Vector2(-4, 4), Vector2(-6, 12), Vector2(-22, 30), Vector2(-36, 26), Vector2(-37, 12)],
	[Vector2(-6, -2), Vector2(-10, 0), Vector2(-36, 6), Vector2(-42, 16), Vector2(-34, 11)],
	[Vector2(-4, -10), Vector2(-3, -21), Vector2(-20, -35), Vector2(-37, -26), Vector2(-40, -7)]
]
const BOB := [-1, 0, 2, 4, 2, 0]
const SEAT_PITCH := [0.04, 0.0, -0.05, -0.08, -0.035, 0.02]
const VARIANT_CACHE_LIMIT := 96
static var _frames: Dictionary = {}
static var _variant_frames: Dictionary = {}
static var _variant_order: Array[String] = []

## Data-driven silhouette, anatomy and socket parameters for each of the 6 dragon breeds.
## Seat is placed at the base of the neck, clearly in front of the wing roots on the dorsal back.
const BREEDS := {
	"spirewing": {
		"build": "lean",
		"torso_points": [Vector2(47, 58), Vector2(56, 54.5), Vector2(66, 50.5), Vector2(74, 48.5)],
		"torso_radii": [8.6, 9.5, 9.6, 8.6],
		"chest_capsule": [Vector2(64, 55), Vector2(75, 53.5), 6.8, 7.4],
		"neck_points": [Vector2(74, 48.5), Vector2(85, 45), Vector2(84, 27), Vector2(98, 20)],
		"neck_radii": [8.0, 4.2],
		"head_pos": Vector2(100, 20),
		"head_size": Vector2(14, 3),
		"head_radii": [5.6, 2.4, 3.8, 1.6, 2.2],
		"horn_style": "spire",
		"horn_length": 20.0,
		"wing_scale": Vector2(0.88, 1.08),
		"wing_offset": Vector2(-2, -2),
		"wing_flank": Vector2(-16, 9),
		"wing_scallop": 0.30,
		"wing_arm_scale": 0.95,
		"tail_points": [Vector2(45, 59), Vector2(29, 66), Vector2(13, 74), Vector2(6, 56)],
		"tail_radii": [7.6, 1.1, 0.82],
		"tail_style": "spade",
		"far_hip": Vector2(44, 59),
		"near_hip": Vector2(51, 61),
		"leg_stance": [Vector2(7, 9), Vector2(1, 20), Vector2(9, 23.5)],
		"leg_thick": 0.95,
		"seat_px": Vector2(72, 45),
		"neck_root_px": Vector2(74, 45),
		"wing_roots_px": {"left": Vector2(51, 44), "right": Vector2(58, 46)}
	},
	"broadmantle": {
		"build": "heavy",
		"torso_points": [Vector2(45, 57), Vector2(55, 54), Vector2(65, 50), Vector2(74, 48)],
		"torso_radii": [11.6, 12.6, 12.2, 10.8],
		"chest_capsule": [Vector2(57, 59), Vector2(75, 53.5), 7.5, 8.0],
		"neck_points": [Vector2(74, 48), Vector2(83, 44.5), Vector2(85, 33), Vector2(95, 26.5)],
		"neck_radii": [10.0, 5.6],
		"head_pos": Vector2(97, 26),
		"head_size": Vector2(15, 3.5),
		"head_radii": [6.8, 3.4, 4.8, 2.4, 3.2],
		"horn_style": "bull",
		"horn_length": 22.0,
		"wing_scale": Vector2(1.14, 1.05),
		"wing_offset": Vector2(-3, 1),
		"wing_flank": Vector2(-22, 13),
		"wing_scallop": 0.14,
		"wing_arm_scale": 1.25,
		"tail_points": [Vector2(44, 58), Vector2(28, 63), Vector2(15, 69), Vector2(7, 63)],
		"tail_radii": [10.6, 2.8, 0.72],
		"tail_style": "mace",
		"far_hip": Vector2(42, 58),
		"near_hip": Vector2(52, 60),
		"leg_stance": [Vector2(9, 8.5), Vector2(3, 19.5), Vector2(12, 23.5)],
		"leg_thick": 1.26,
		"seat_px": Vector2(71, 43),
		"neck_root_px": Vector2(73, 43),
		"wing_roots_px": {"left": Vector2(49, 43), "right": Vector2(56, 45)}
	},
	"reedrunner": {
		"build": "long",
		"torso_points": [Vector2(42, 60), Vector2(54, 57.5), Vector2(66, 54), Vector2(77, 51.5)],
		"torso_radii": [7.5, 8.4, 8.6, 7.6],
		"chest_capsule": [Vector2(66, 58), Vector2(78, 56.5), 6.4, 7.2],
		"neck_points": [Vector2(77, 51.5), Vector2(88, 49), Vector2(92, 36), Vector2(104, 29)],
		"neck_radii": [7.0, 3.5],
		"head_pos": Vector2(105, 28),
		"head_size": Vector2(16, 2.5),
		"head_radii": [4.6, 1.9, 3.0, 1.3, 1.7],
		"horn_style": "reed",
		"horn_length": 23.0,
		"wing_scale": Vector2(1.04, 0.72),
		"wing_offset": Vector2(-4, 4),
		"wing_flank": Vector2(-15, 6),
		"wing_scallop": 0.24,
		"wing_arm_scale": 0.80,
		"tail_points": [Vector2(41, 60.5), Vector2(26, 64), Vector2(11, 67), Vector2(2, 62)],
		"tail_radii": [6.4, 0.8, 0.90],
		"tail_style": "dart",
		"far_hip": Vector2(41, 60),
		"near_hip": Vector2(49, 61.5),
		"leg_stance": [Vector2(9, 8), Vector2(1, 19.5), Vector2(10, 22.5)],
		"leg_thick": 0.76,
		"seat_px": Vector2(75, 49),
		"neck_root_px": Vector2(77, 49),
		"wing_roots_px": {"left": Vector2(53, 49), "right": Vector2(60, 51)}
	},
	"ironcrest": {
		"build": "compact",
		"torso_points": [Vector2(52, 57), Vector2(59, 53.5), Vector2(66, 49.5), Vector2(73, 47.5)],
		"torso_radii": [9.8, 11.4, 11.4, 9.8],
		"chest_capsule": [Vector2(63, 55.5), Vector2(74, 52), 7.2, 7.6],
		"neck_points": [Vector2(73, 47.5), Vector2(81, 43), Vector2(81, 29), Vector2(92, 22)],
		"neck_radii": [8.8, 5.0],
		"head_pos": Vector2(94, 22),
		"head_size": Vector2(12, 3),
		"head_radii": [6.2, 3.0, 4.4, 2.2, 3.0],
		"horn_style": "crest",
		"horn_length": 17.0,
		"wing_scale": Vector2(0.84, 0.96),
		"wing_offset": Vector2(-1, -1),
		"wing_flank": Vector2(-16, 10),
		"wing_scallop": 0.34,
		"wing_arm_scale": 1.12,
		"tail_points": [Vector2(50, 58), Vector2(36, 62), Vector2(21, 66), Vector2(11, 50)],
		"tail_radii": [8.8, 2.0, 0.78],
		"tail_style": "halberd",
		"far_hip": Vector2(48, 58),
		"near_hip": Vector2(55, 60),
		"leg_stance": [Vector2(7, 9), Vector2(2, 20), Vector2(10, 23.5)],
		"leg_thick": 1.12,
		"seat_px": Vector2(70, 43),
		"neck_root_px": Vector2(72, 43),
		"wing_roots_px": {"left": Vector2(52, 43), "right": Vector2(58, 45)}
	},
	"stormkeel": {
		"build": "barrel",
		"torso_points": [Vector2(46, 57), Vector2(56, 54), Vector2(67, 50), Vector2(75, 48)],
		"torso_radii": [10.4, 11.8, 11.8, 10.0],
		"chest_capsule": [Vector2(58, 59), Vector2(77, 54), 7.4, 8.0],
		"neck_points": [Vector2(75, 48), Vector2(85, 44), Vector2(84, 29), Vector2(97, 23)],
		"neck_radii": [9.2, 4.8],
		"head_pos": Vector2(99, 23),
		"head_size": Vector2(14, 3),
		"head_radii": [6.0, 2.6, 4.2, 1.8, 2.5],
		"horn_style": "prow",
		"horn_length": 21.0,
		"wing_scale": Vector2(1.10, 1.03),
		"wing_offset": Vector2(-3, -1),
		"wing_flank": Vector2(-21, 12),
		"wing_scallop": 0.40,
		"wing_arm_scale": 1.20,
		"tail_points": [Vector2(45, 58.5), Vector2(29, 65), Vector2(14, 73), Vector2(6, 58)],
		"tail_radii": [9.2, 1.8, 0.76],
		"tail_style": "fluke",
		"far_hip": Vector2(43, 59),
		"near_hip": Vector2(51, 61),
		"leg_stance": [Vector2(8.5, 9), Vector2(2, 20), Vector2(11, 23.5)],
		"leg_thick": 1.20,
		"seat_px": Vector2(73, 44),
		"neck_root_px": Vector2(75, 44),
		"wing_roots_px": {"left": Vector2(50, 44), "right": Vector2(57, 46)}
	},
	"duskfin": {
		"build": "sleek",
		"torso_points": [Vector2(45, 59), Vector2(56, 56), Vector2(67, 52), Vector2(75, 49.5)],
		"torso_radii": [8.2, 9.2, 9.2, 8.2],
		"chest_capsule": [Vector2(65, 56.5), Vector2(76, 55), 6.6, 7.2],
		"neck_points": [Vector2(75, 49.5), Vector2(87, 46), Vector2(86, 30), Vector2(100, 24)],
		"neck_radii": [7.4, 3.8],
		"head_pos": Vector2(101, 24),
		"head_size": Vector2(15, 2.5),
		"head_radii": [5.0, 2.1, 3.4, 1.4, 1.8],
		"horn_style": "frill",
		"horn_length": 19.5,
		"wing_scale": Vector2(1.02, 0.86),
		"wing_offset": Vector2(-4, 2),
		"wing_flank": Vector2(-20, 10),
		"wing_scallop": 0.10,
		"wing_arm_scale": 0.84,
		"tail_points": [Vector2(44, 59.5), Vector2(28, 67), Vector2(14, 76), Vector2(7, 61)],
		"tail_radii": [7.0, 1.0, 0.84],
		"tail_style": "fan",
		"far_hip": Vector2(44, 59.5),
		"near_hip": Vector2(51, 61),
		"leg_stance": [Vector2(7.5, 9), Vector2(1.5, 20), Vector2(9.5, 23.5)],
		"leg_thick": 0.86,
		"seat_px": Vector2(73, 47),
		"neck_root_px": Vector2(75, 47),
		"wing_roots_px": {"left": Vector2(52, 47), "right": Vector2(59, 49)}
	}
}

static func breed_spec(morph_id: String) -> Dictionary:
	return BREEDS.get(morph_id, BREEDS["spirewing"])

class Layer extends RefCounted:
	var height := PackedFloat32Array()
	var normal := PackedVector3Array()
	var material := PackedByteArray()
	var extra := PackedFloat32Array()
	var far := false
	var is_wing := false

	func _init(distant: bool = false) -> void:
		far = distant
		height.resize(128 * 96); height.fill(-1.0)
		normal.resize(128 * 96); normal.fill(Vector3(0, 0, 1))
		material.resize(128 * 96)
		extra.resize(128 * 96)

	func capsule(a: Vector2, b: Vector2, ra: float, rb: float, mat: int = 1) -> void:
		var radius := maxf(ra, rb)
		var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
		var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil()).min(Vector2i(128, 96))
		var axis := b - a
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				var point := Vector2(x + 0.5, y + 0.5)
				var t := clampf((point - a).dot(axis) / maxf(axis.length_squared(), 0.000001), 0, 1)
				var delta := point - a.lerp(b, t)
				var r := lerpf(ra, rb, t)
				if delta.length_squared() >= r * r: continue
				var h := sqrt(maxf(0, 1 - delta.length_squared() / (r * r)))
				var index := y * 128 + x
				if h * r <= height[index]: continue
				height[index] = h * r
				normal[index] = Vector3(delta.x / r, delta.y / r, h).normalized()
				material[index] = mat

	func chain(points: PackedVector2Array, first: float, last: float, mat: int = 1, exponent: float = 1.0) -> void:
		var count := points.size() - 1
		for i in count:
			capsule(points[i], points[i + 1], lerpf(first, last, pow(float(i) / count, exponent)), lerpf(first, last, pow(float(i + 1) / count, exponent)), mat)

	func polygon(points: PackedVector2Array, mat: int) -> void:
		var lo := Vector2(128, 96)
		var hi := Vector2.ZERO
		for p: Vector2 in points:
			lo = lo.min(p)
			hi = hi.max(p)
		var x0 := maxi(0, floori(lo.x))
		var x1 := mini(128, ceili(hi.x) + 1)
		var y0 := maxi(0, floori(lo.y))
		var y1 := mini(96, ceili(hi.y) + 1)
		for y in range(y0, y1):
			for x in range(x0, x1):
				var i := y * 128 + x
				if height[i] >= 0: continue
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					height[i] = 0.01
					material[i] = mat

static func has_gem(gem_id: String) -> bool:
	return PALETTES.has(gem_id)

static func has_morph(morph_id: String) -> bool:
	return morph_id in MORPHS

static func palette_for(gem_id: String) -> Dictionary:
	return PALETTES.get(gem_id, PALETTES["sapphire"])

static func frame_index(pose: String, progress: float) -> int:
	if pose in ["rest", "dead", "prone"]: return 1
	return clampi(floori(clampf(progress, 0, 1) * FRAME_COUNT), 0, FRAME_COUNT - 1)

static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / steps
		points.append(a * pow(1 - t, 3) + b * 3 * pow(1 - t, 2) * t + c * 3 * (1 - t) * t * t + d * t * t * t)
	return points

static func _scallop(a: Vector2, b: Vector2, wrist: Vector2, k: float = 0.28) -> PackedVector2Array:
	var points := PackedVector2Array()
	var control := ((a + b) * 0.5).lerp(wrist, k)
	for i in 9:
		var t := float(i) / 8
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points

static func _morph_wing_pose(pose: Array, morph_id: String) -> Array:
	var spec := breed_spec(morph_id)
	var scale: Vector2 = spec["wing_scale"]
	var offset: Vector2 = spec["wing_offset"]
	var out: Array = []
	for idx in pose.size():
		var p: Vector2 = pose[idx]
		out.append(p * scale + (offset if idx >= 2 else offset * 0.35))
	return out

static func _wing_flank_offset(morph_id: String) -> Vector2:
	return breed_spec(morph_id)["wing_flank"]

static func _wing_scallop_k(morph_id: String) -> float:
	return float(breed_spec(morph_id)["wing_scallop"])

static func _wing_points(shoulder: Vector2, pose: Array, morph_id: String = "spirewing") -> PackedVector2Array:
	var mpose := _morph_wing_pose(pose, morph_id)
	var wrist: Vector2 = shoulder + mpose[1]
	var first: Vector2 = shoulder + mpose[2]
	var middle: Vector2 = shoulder + mpose[3]
	var last: Vector2 = shoulder + mpose[4]
	var flank := shoulder + _wing_flank_offset(morph_id)
	var k := _wing_scallop_k(morph_id)
	var points := PackedVector2Array([shoulder, shoulder + mpose[0], wrist, first])
	points.append_array(_scallop(first, middle, wrist, k).slice(1))
	points.append_array(_scallop(middle, last, wrist, k).slice(1))
	points.append_array(_scallop(last, flank, wrist, k * 0.65).slice(1))
	return points

static func _far_pose(pose: Array) -> Array:
	var out: Array = []
	for point: Vector2 in pose: out.append(point * Vector2(0.86, 0.9) - Vector2(2, 2))
	return out

static func _wing(layer: Layer, shoulder: Vector2, pose: Array, morph_id: String = "spirewing") -> void:
	layer.is_wing = true
	var spec := breed_spec(morph_id)
	var mpose := _morph_wing_pose(pose, morph_id)
	var elbow: Vector2 = shoulder + mpose[0]
	var wrist: Vector2 = shoulder + mpose[1]
	var fingers := [shoulder + mpose[2], shoulder + mpose[3], shoulder + mpose[4]]
	var poly := _wing_points(shoulder, pose, morph_id)
	layer.polygon(poly, 4)
	var bones := [[wrist, fingers[0]], [wrist, fingers[1]], [wrist, fingers[2]], [shoulder, elbow], [elbow, wrist]]
	var lo := Vector2(128, 96)
	var hi := Vector2.ZERO
	for p: Vector2 in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, floori(lo.y)), mini(SIZE.y, ceili(hi.y) + 1)):
		for x in range(maxi(0, floori(lo.x)), mini(SIZE.x, ceili(hi.x) + 1)):
			var index := y * SIZE.x + x
			if layer.material[index] != 4: continue
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := 99.0
			for bone: Array in bones:
				distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, bone[0], bone[1])))
			layer.extra[index] = clampf(distance / 7, 0, 1) * 0.55 + clampf(point.distance_to(wrist) / 40, 0, 1) * 0.35 + (0.08 if point.y < shoulder.y else 0.0)
	var k := _wing_scallop_k(morph_id)
	var edge := _scallop(fingers[0], fingers[1], wrist, k)
	edge.append_array(_scallop(fingers[1], fingers[2], wrist, k))
	edge.append_array(_scallop(fingers[2], shoulder + _wing_flank_offset(morph_id), wrist, k * 0.65))
	for point: Vector2 in edge:
		var at := Vector2i(point)
		if Rect2i(Vector2i.ZERO, SIZE).has_point(at) and layer.material[at.y * SIZE.x + at.x] == 4:
			layer.material[at.y * SIZE.x + at.x] = 5
	var arm_scale := float(spec["wing_arm_scale"])
	layer.capsule(shoulder, elbow, 3.2 * arm_scale, 2.4 * arm_scale)
	layer.capsule(elbow, wrist, 2.4 * arm_scale, 1.7 * arm_scale)
	var finger_mat := 3 if morph_id == "duskfin" else 1
	for i in 3: layer.capsule(wrist, fingers[i], 1.1, [0.54, 0.48, 0.42][i], finger_mat)
	if morph_id == "duskfin":
		layer.capsule(wrist, (fingers[1] + fingers[2]) * 0.5, 0.95, 0.40, 3)
	var claw_vec := Vector2(3.6, -4.0) if morph_id == "ironcrest" else Vector2(2.2, -2.5)
	layer.capsule(wrist, wrist + claw_vec, 1.5 if morph_id == "ironcrest" else 1.2, 0.5, 3)

static func _leg(layer: Layer, hip: Vector2, bend: float, lift: float, morph_id: String = "spirewing") -> void:
	var spec := breed_spec(morph_id)
	var stance: Array = spec["leg_stance"]
	var knee := hip + (stance[0] as Vector2) + Vector2(0, bend)
	var ankle := hip + (stance[1] as Vector2) + Vector2(0, lift)
	var toe := hip + (stance[2] as Vector2) + Vector2(0, lift)
	var thick := float(spec["leg_thick"])
	layer.capsule(hip, knee, 7.0 * thick, 4.2 * thick)
	if morph_id == "broadmantle":
		layer.capsule(hip + Vector2(-2, 1), knee + Vector2(-1, 0), 7.8 * thick, 4.5 * thick)
	layer.capsule(knee, ankle, 3.6 * thick, 2.4 * thick)
	layer.capsule(ankle, toe, 2.4 * thick, 1.8 * thick)
	layer.capsule(ankle + Vector2(-1, 1), ankle + Vector2(-4, 3.5), 1.6 * thick, 0.8 * thick)
	if morph_id == "duskfin":
		layer.polygon(PackedVector2Array([knee + Vector2(-2, -1), knee + Vector2(-8, 4), ankle + Vector2(-2, 0)]), 4)
		layer.capsule(knee + Vector2(-1, 0), knee + Vector2(-7, 4), 0.85, 0.35, 3)
	elif morph_id == "ironcrest":
		layer.polygon(PackedVector2Array([knee + Vector2(1, -2), knee + Vector2(6, -1), knee + Vector2(2, 2)]), 3)
	elif morph_id == "stormkeel":
		layer.capsule(ankle + Vector2(-1, 0), ankle + Vector2(-6, 1.5), 1.5, 0.45, 3)
	for tx: float in [0.0, -3.0]:
		var tip := toe + Vector2(1 + tx, -0.5)
		layer.capsule(tip, tip + Vector2(2.4, 1.6), 1.1 * clampf(thick, 0.9, 1.2), 0.4, 3)
	layer.capsule(ankle + Vector2(-4, 3.5), ankle + Vector2(-6, 4.5), 0.9, 0.3, 3)

static func _shade(layer: Layer, pal: Dictionary) -> PackedColorArray:
	var output := PackedColorArray()
	output.resize(SIZE.x * SIZE.y)
	var light := Vector3(-0.60, -0.75, 0.35).normalized()
	var skin: Array = pal["skin_far"] if layer.far else pal["skin"]
	var belly: Array = pal["belly_far"] if layer.far else pal["belly"]
	var membrane: Array = pal["membrane_far"] if layer.far else pal["membrane"]
	var gem: Array = pal["gem"]
	for y in SIZE.y:
		for x in SIZE.x:
			var i := y * SIZE.x + x
			var mat := layer.material[i]
			if mat == 0: continue
			var lambert := layer.normal[i].dot(light)
			var dither := (0.06 if (x + y) % 2 else -0.06) if (floori(float(x) / 2) + y) % 3 == 0 else 0.0
			match mat:
				1, 2:
					if mat == 2 and layer.normal[i].y > 0.30:
						var index := clampi(int((lambert + dither + 0.20) * 3), 0, 3)
						if y % 3 == 0: index = maxi(0, index - 1)
						output[i] = belly[index]
					else: output[i] = skin[clampi(int((lambert + dither + 0.12) * 4.4), 0, 5)]
				3: output[i] = gem[clampi(int((lambert + 0.1) * 3.4), 0, 3)]
				4: output[i] = membrane[clampi(int(layer.extra[i] * 4.2), 0, 3)]
				5: output[i] = membrane[4]
	return output

static func _composite(layers: Array, pal: Dictionary) -> Image:
	var cv := PixelCanvas.new(SIZE.x, SIZE.y)
	var outline: Color = pal["outline"]
	var skin: Array = pal["skin"]
	var skin_far: Array = pal["skin_far"]
	for layer: Layer in layers:
		var colors := _shade(layer, pal)
		for y in SIZE.y:
			for x in SIZE.x:
				var i := y * SIZE.x + x
				if layer.material[i] == 0: continue
				var rim := false
				for step: Vector2i in PixelCanvas.N4:
					var at := Vector2i(x, y) + step
					if not Rect2i(Vector2i.ZERO, SIZE).has_point(at) or layer.material[at.y * SIZE.x + at.x] == 0: rim = true
				var dark: Color = skin_far[0] if layer.far else skin[0]
				cv.buf[i] = (outline if layer.is_wing else dark) if rim and cv.buf[i].a > 0 else colors[i]
	var solid := cv.buf.duplicate()
	for y in SIZE.y:
		for x in SIZE.x:
			if solid[y * SIZE.x + x].a > 0: continue
			for step: Vector2i in PixelCanvas.N4:
				var at := Vector2i(x, y) + step
				if Rect2i(Vector2i.ZERO, SIZE).has_point(at) and solid[at.y * SIZE.x + at.x].a > 0:
					cv.buf[y * SIZE.x + x] = outline
	return cv.to_image()

static func _draw_tail_features(tail: Layer, tail_points: PackedVector2Array, morph_id: String) -> void:
	var spec := breed_spec(morph_id)
	var tr: Array = spec["tail_radii"]
	tail.chain(tail_points, float(tr[0]), float(tr[1]), 2, float(tr[2]))
	var tip := tail_points[-1]
	var prev := tail_points[maxi(0, tail_points.size() - 5)]
	match String(spec["tail_style"]):
		"mace":
			tail.capsule(prev, tip + Vector2(-2, 0), 4.2, 4.8, 1)
			tail.polygon(PackedVector2Array([tip + Vector2(-1, -2), tip + Vector2(-6, -8), tip + Vector2(2, -4)]), 3)
			tail.polygon(PackedVector2Array([tip + Vector2(-1, 2), tip + Vector2(-6, 8), tip + Vector2(2, 4)]), 3)
			tail.polygon(PackedVector2Array([prev + Vector2(1, -2), prev + Vector2(-2, -7), prev + Vector2(4, -3)]), 3)
		"dart":
			tail.polygon(PackedVector2Array([prev + Vector2(3, 0), tip + Vector2(-3, -4), tip + Vector2(-6, 0), tip + Vector2(-3, 4)]), 3)
		"halberd":
			tail.polygon(PackedVector2Array([prev + Vector2(2, 1), tip + Vector2(-5, -9), tip + Vector2(-9, -1), tip + Vector2(-4, 6)]), 3)
			for idx: int in [10, 17, 23]:
				var tp := tail_points[idx]
				tail.polygon(PackedVector2Array([tp + Vector2(-2, 0), tp + Vector2(-3, -6), tp + Vector2(2, 0)]), 3)
		"fluke":
			tail.polygon(PackedVector2Array([prev + Vector2(3, 0), tip + Vector2(-6, -8), tip + Vector2(-2, 0), tip + Vector2(-6, 8)]), 4)
			tail.capsule(prev + Vector2(1, 0), tip + Vector2(-5, -7), 1.1, 0.4, 3)
			tail.capsule(prev + Vector2(1, 0), tip + Vector2(-5, 7), 1.1, 0.4, 3)
		"fan":
			tail.polygon(PackedVector2Array([prev + Vector2(4, 0), tip + Vector2(-5, -8), tip + Vector2(-8, -3), tip + Vector2(-8, 3), tip + Vector2(-4, 8)]), 4)
			for dy: float in [-7.0, -2.5, 2.5, 7.0]:
				tail.capsule(prev + Vector2(2, 0), tip + Vector2(-6, dy), 0.9, 0.3, 3)
		_:
			tail.polygon(PackedVector2Array([tip + Vector2(-1, 2), tip + Vector2(-5, -5), tip + Vector2(3, -3)]), 1)
			tail.capsule(tip + Vector2(1, -1), tip + Vector2(-4, -5), 0.9, 0.35, 3)

static func _draw_breed_body_and_head(body: Layer, shift: Vector2, morph_id: String) -> Vector2:
	var spec := breed_spec(morph_id)
	var t_pts: Array = spec["torso_points"]
	var radii: Array = spec["torso_radii"]
	for i in 3:
		body.capsule((t_pts[i] as Vector2) + shift, (t_pts[i + 1] as Vector2) + shift, float(radii[i]), float(radii[i + 1]), 2)
	var chest: Array = spec["chest_capsule"]
	body.capsule((chest[0] as Vector2) + shift, (chest[1] as Vector2) + shift, float(chest[2]), float(chest[3]), 2)
	if morph_id == "stormkeel":
		body.capsule(Vector2(57, 61) + shift, Vector2(77, 55.5) + shift, 6.2, 7.2, 2)
		body.polygon(PackedVector2Array([Vector2(61, 65) + shift, Vector2(80, 57.5) + shift, Vector2(75, 67) + shift]), 3)
	elif morph_id == "broadmantle":
		body.capsule(Vector2(56, 60) + shift, Vector2(74, 54) + shift, 6.4, 6.8, 2)
	var n_pts: Array = spec["neck_points"]
	var n_rad: Array = spec["neck_radii"]
	var neck_start := float(n_rad[0])
	var neck_end := float(n_rad[1])
	var neck := _bezier((n_pts[0] as Vector2) + shift, (n_pts[1] as Vector2) + shift, (n_pts[2] as Vector2) + shift, (n_pts[3] as Vector2) + shift, 20)
	body.chain(neck, neck_start, neck_end, 2)
	var head: Vector2 = (spec["head_pos"] as Vector2) + shift
	var h_size: Vector2 = spec["head_size"]
	var h_rad: Array = spec["head_radii"]
	body.capsule(head, head + h_size, float(h_rad[0]), float(h_rad[1]))
	body.capsule(head + Vector2(1, 4), head + Vector2(h_size.x - 2, 6), float(h_rad[2]), float(h_rad[3]), 2)
	body.capsule(head + Vector2(-1, -2), head + Vector2(6, -3), float(h_rad[4]), 1.6)
	match String(spec["horn_style"]):
		"bull":
			for horn: Vector3 in [Vector3(0, 0, 1.15), Vector3(2, 1, 0.9)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -3 + horn.y), head + Vector2(-9 + horn.x, -9 + horn.y), head + Vector2(-16 + horn.x * 2, -5 + horn.y), head + Vector2(-21 + horn.x * 2, -12 + horn.y), 14)
				body.chain(points, 3.1 * horn.z, 0.75, 3)
			body.polygon(PackedVector2Array([head + Vector2(-2, 1), head + Vector2(-10, 5), head + Vector2(-2, 5)]), 3)
			body.polygon(PackedVector2Array([head + Vector2(-4, 4), head + Vector2(-11, 8), head + Vector2(-3, 7)]), 1)
			body.capsule(head + Vector2(3, 6), head + Vector2(12, 7.5), 2.4, 1.8, 1)
		"reed":
			for horn: Vector3 in [Vector3(0, 0, 0.92), Vector3(2, 1, 0.78)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -3 + horn.y), head + Vector2(-9 + horn.x, -6 + horn.y), head + Vector2(-16 + horn.x * 2, -5 + horn.y), head + Vector2(-22 + horn.x * 2, -3 + horn.y), 14)
				body.chain(points, 1.9 * horn.z, 0.35, 3)
			body.capsule(head + Vector2(-2, 0), head + Vector2(-15, 1), 1.3, 0.35, 3)
			body.polygon(PackedVector2Array([head + Vector2(-3, 2), head + Vector2(-10, 4), head + Vector2(-3, 5)]), 1)
		"crest":
			for horn: Vector3 in [Vector3(0, 0, 1.05), Vector3(2, 1, 0.85)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -4 + horn.y), head + Vector2(-5 + horn.x, -14 + horn.y), head + Vector2(-12 + horn.x * 2, -16 + horn.y), head + Vector2(-16 + horn.x * 2, -12 + horn.y), 14)
				body.chain(points, 2.5 * horn.z, 0.6, 3)
			for cx: float in [4.0, 1.0, -2.0, -5.0, -8.0]:
				var cbase := head + Vector2(cx, -4)
				body.polygon(PackedVector2Array([cbase + Vector2(-2, 1), cbase + Vector2(-4, -9), cbase + Vector2(2, 1)]), 3)
			body.polygon(PackedVector2Array([head + Vector2(6, 6), head + Vector2(10, 9.5), head + Vector2(11, 6)]), 3)
			body.polygon(PackedVector2Array([head + Vector2(-3, 2), head + Vector2(-9, 5), head + Vector2(-3, 5)]), 1)
		"prow":
			for horn: Vector3 in [Vector3(0, 0, 1.1), Vector3(2, 1, 0.85)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -4 + horn.y), head + Vector2(-8 + horn.x, -12 + horn.y), head + Vector2(-15 + horn.x * 2, -9 + horn.y), head + Vector2(-20 + horn.x * 2, -3 + horn.y), 14)
				body.chain(points, 2.7 * horn.z, 0.6, 3)
			body.polygon(PackedVector2Array([head + Vector2(8, 0), head + Vector2(13, -6), head + Vector2(14, 1)]), 3)
			body.polygon(PackedVector2Array([head + Vector2(-3, 2), head + Vector2(-9, 5), head + Vector2(-3, 5)]), 1)
		"frill":
			for horn: Vector3 in [Vector3(0, 0, 0.95), Vector3(2, 1, 0.78)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -4 + horn.y), head + Vector2(-7 + horn.x, -10 + horn.y), head + Vector2(-14 + horn.x * 2, -10 + horn.y), head + Vector2(-19 + horn.x * 2, -6 + horn.y), 14)
				body.chain(points, 2.0 * horn.z, 0.42, 3)
			body.polygon(PackedVector2Array([head + Vector2(-2, 0), head + Vector2(-12, -3), head + Vector2(-13, 4), head + Vector2(-3, 6)]), 4)
			body.capsule(head + Vector2(-2, 0), head + Vector2(-12, -2), 0.9, 0.3, 3)
			body.capsule(head + Vector2(-2, 2), head + Vector2(-12, 1), 0.9, 0.3, 3)
			body.capsule(head + Vector2(-2, 4), head + Vector2(-11, 4), 0.9, 0.3, 3)
		_:
			for horn: Vector3 in [Vector3(0, 0, 1), Vector3(2, 1, 0.8)]:
				var points := _bezier(head + Vector2(-1 + horn.x, -4 + horn.y), head + Vector2(-6 + horn.x, -13 + horn.y), head + Vector2(-14 + horn.x * 2, -14 + horn.y), head + Vector2(-20 + horn.x * 3, -9 + horn.y), 14)
				body.chain(points, 2.4 * horn.z, 0.5, 3)
			body.polygon(PackedVector2Array([head + Vector2(-3, 2), head + Vector2(-9, 5), head + Vector2(-3, 5)]), 1)
	var spine_mat := 3 if morph_id in ["ironcrest", "stormkeel"] else 1
	var spine_h := 6.0 if morph_id == "ironcrest" else (5.0 if morph_id == "stormkeel" else (2.6 if morph_id == "reedrunner" else 4.2))
	# Keep the base of the neck (t < 0.42) clear of dorsal spines so the saddle and rider sit cleanly on the neck base.
	if morph_id == "duskfin":
		var sail_pts := PackedVector2Array()
		for t: float in [0.42, 0.60, 0.78]:
			var idx := int(t * 20)
			var normal := (neck[idx + 1] - neck[idx]).orthogonal().normalized()
			var base := neck[idx] - normal * lerpf(neck_start, neck_end, float(idx) / 20) * 0.75
			sail_pts.append(base)
			body.capsule(base, base - normal * 5.0, 0.9, 0.3, 3)
		if sail_pts.size() == 3:
			body.polygon(PackedVector2Array([sail_pts[0], sail_pts[0] + Vector2(-4, -3), sail_pts[1] + Vector2(-4, -3), sail_pts[2] + Vector2(-3, -2), sail_pts[2]]), 4)
	else:
		for t: float in [0.46, 0.64, 0.80]:
			var i := int(t * 20)
			var angle := (neck[i + 1] - neck[i]).angle()
			var tangent := Vector2(cos(angle), sin(angle))
			var normal := Vector2(sin(angle), -cos(angle))
			var base := neck[i] + normal * lerpf(neck_start, neck_end, float(i) / 20) * 0.8
			body.polygon(PackedVector2Array([base - tangent * 2, base + normal * spine_h - tangent * 3, base + tangent * 1.5]), spine_mat)
	for point: Vector2 in [Vector2(47, 50), Vector2(40, 54), Vector2(33, 58)]:
		body.polygon(PackedVector2Array([point + shift + Vector2(-2, 2), point + shift + Vector2(-3, -spine_h * 0.8), point + shift + Vector2(2, 1)]), spine_mat)
	return head

static func _render_frame(gem_id: String, morph_id: String, index: int) -> Image:
	index = posmod(index, FRAME_COUNT)
	var pal := palette_for(gem_id)
	var spec := breed_spec(morph_id)
	var pose: Array = WING_POSES[index]
	var shift := Vector2(0, -BOB[index])
	var wing_roots: Dictionary = spec["wing_roots_px"]
	var far_shoulder: Vector2 = (wing_roots["left"] as Vector2) + shift
	var near_shoulder: Vector2 = (wing_roots["right"] as Vector2) + shift
	var far_wing := Layer.new(true)
	var far_leg := Layer.new(true)
	var tail := Layer.new()
	var body := Layer.new()
	var near_leg := Layer.new()
	var near_wing := Layer.new()
	_wing(far_wing, far_shoulder, _far_pose(pose), morph_id)
	_leg(far_leg, (spec["far_hip"] as Vector2) + shift, 1, -shift.y, morph_id)
	var sway := sin(float(index) / FRAME_COUNT * TAU) * 2
	var t_pts: Array = spec["tail_points"]
	var tail_points := _bezier((t_pts[0] as Vector2) + shift, (t_pts[1] as Vector2) + shift, (t_pts[2] as Vector2) + Vector2(0, sway), (t_pts[3] as Vector2) + Vector2(0, sway), 30)
	_draw_tail_features(tail, tail_points, morph_id)
	var head := _draw_breed_body_and_head(body, shift, morph_id)
	_leg(near_leg, (spec["near_hip"] as Vector2) + shift, 0, -shift.y, morph_id)
	_wing(near_wing, near_shoulder, pose, morph_id)
	var image := _composite([far_wing, far_leg, tail, body, near_leg, near_wing], pal)
	var outline: Color = pal["outline"]
	var eye_colors: Array = pal["eye"]
	var gem_colors: Array = pal["gem"]
	var tooth_color: Color = pal["tooth"]
	var hl := int((spec["head_size"] as Vector2).x)
	var eye := Vector2i(head + Vector2(3, -1))
	image.set_pixelv(eye, eye_colors[0]); image.set_pixelv(eye + Vector2i(1, 0), eye_colors[1])
	for step: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]: image.set_pixelv(eye + step, outline)
	image.set_pixelv(Vector2i(head + Vector2(hl - 2, 1)), outline)
	for i in range(3, hl - 1): image.set_pixelv(Vector2i(head + Vector2(i, 4)), outline)
	var teeth_x: Array = [4, 7, 9] if hl <= 12 else ([5, 8, 11, 13] if hl >= 16 else [5, 8, 11])
	for x: int in teeth_x: image.set_pixelv(Vector2i(head + Vector2(x, 5)), tooth_color)
	for glint_step: Vector2i in [Vector2i(-8, -11), Vector2i(-8, -6), Vector2i(-4, -9), Vector2i(-5, -5)]:
		var gp := Vector2i(head) + glint_step
		if Rect2i(Vector2i.ZERO, SIZE).has_point(gp) and body.material[gp.y * SIZE.x + gp.x] == 3:
			image.set_pixelv(gp, gem_colors[4] if glint_step.x <= -7 else gem_colors[3])
	var output := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	output.blit_rect(image, Rect2i(0, 0, SIZE.x, SIZE.y - 3), Vector2i(0, 3))
	return output

static func frame(index: int) -> Image:
	index = posmod(index, FRAME_COUNT)
	if _frames.has(index): return _frames[index]
	var output := _render_frame("sapphire", "spirewing", index)
	_frames[index] = output
	return output

static func frame_for(gem_id: String, morph_id: String, index: int) -> Image:
	index = posmod(index, FRAME_COUNT)
	if gem_id == "sapphire" and morph_id == "spirewing":
		return frame(index)
	var key := "%s_%s:%d" % [gem_id, morph_id, index]
	if _variant_frames.has(key):
		_variant_order.erase(key); _variant_order.append(key)
		return _variant_frames[key]
	var output := _render_frame(gem_id, morph_id, index)
	_variant_frames[key] = output
	_variant_order.append(key)
	while _variant_order.size() > VARIANT_CACHE_LIMIT:
		_variant_frames.erase(_variant_order.pop_front())
	return output

static func _coordinates(points: PackedVector2Array) -> Array:
	var out: Array = []
	for point: Vector2 in points: out.append([point.x, point.y])
	return out

static func _region(owner: String, polygon: Array, start: Array, end: Array) -> Dictionary:
	return {"owner_part_id": owner, "polygons": [polygon], "anchor_start_px": start, "anchor_end_px": end}

static func metadata(index: int) -> Dictionary:
	return metadata_for("sapphire", "spirewing", index)

static func metadata_for(gem_id: String, morph_id: String, index: int) -> Dictionary:
	index = posmod(index, FRAME_COUNT)
	var spec := breed_spec(morph_id)
	var d: int = 3 - BOB[index]
	var hp: Vector2 = spec["head_pos"]
	var hx := int(hp.x)
	var hy := int(hp.y)
	var hl := int((spec["head_size"] as Vector2).x)
	var seat: Vector2 = spec["seat_px"]
	var neck_root: Vector2 = spec["neck_root_px"]
	var wing_roots: Dictionary = spec["wing_roots_px"]
	var far_wing: Vector2 = wing_roots["left"]
	var near_wing: Vector2 = wing_roots["right"]
	var cut_y: int = hy + 14 + d
	var cut_x0: int = hx - 19
	var cut_x1: int = hx - 9
	var head: Array = [[hx - 24, 0], [128, 0], [128, cut_y], [cut_x1, cut_y], [cut_x0, cut_y + 2]]
	var jaw: Array = [[hx - 1, hy + 4 + d], [hx + 3, hy + 4 + d], [hx + hl + 2, hy + 6 + d], [hx + hl + 1, hy + 12 + d], [hx - 2, hy + 10 + d]]
	var neck: Array = [[int(neck_root.x) - 6, int(neck_root.y) - 4 + d], [cut_x0, cut_y + 2], [cut_x1, cut_y], [cut_x1 + 5, int(neck_root.y) + 2 + d], [int(neck_root.x) + 4, int(neck_root.y) + 14 + d]]
	var t_pts: Array = spec["torso_points"]
	var t_start: Vector2 = t_pts[0]
	var t_end: Vector2 = t_pts[3]
	var tail_pts: Array = spec["tail_points"]
	var tail_start: Vector2 = tail_pts[0]
	var tail_end: Vector2 = tail_pts[3]
	var regions := {
		"torso": _region("body", [[int(t_start.x) - 9, 40 + d], [int(t_end.x) + 4, 36 + d], [int(t_end.x) + 8, 68 + d], [int(t_start.x) - 4, 74 + d]], [t_start.x, t_start.y + d], [t_end.x, t_end.y + d]),
		"neck": _region("body", neck, [neck_root.x, neck_root.y + d], [cut_x1 - 4, cut_y + 1]),
		"head": _region("head", head, [cut_x1 - 4, cut_y + 1], [hx + 5, hy + d]),
		"jaw": _region("jaw", jaw, [hx, hy + 5 + d], [hx + hl - 1, hy + 7 + d]),
		"tail": _region("body", [[0, 42], [int(tail_start.x) + 2, 48 + d], [int(tail_start.x) + 8, 72 + d], [10, 88], [0, 78]], [tail_start.x, tail_start.y + d], [tail_end.x, tail_end.y + d])
	}
	regions["neck"]["cut_line_px"] = [[cut_x0, cut_y + 2], [cut_x1, cut_y], [128, cut_y]]
	regions["neck"]["cut_point_px"] = [cut_x1 - 4, cut_y + 1]
	var stance: Array = spec["leg_stance"]
	for side: String in ["l", "r"]:
		var distant := side == "l"
		var shoulder := Vector2(far_wing.x, far_wing.y + d) if distant else Vector2(near_wing.x, near_wing.y + d)
		var base_pose: Array = _far_pose(WING_POSES[index]) if distant else WING_POSES[index]
		var pose: Array = _morph_wing_pose(base_pose, morph_id)
		var elbow: Vector2 = shoulder + pose[0]
		var wrist: Vector2 = shoulder + pose[1]
		var upper := PackedVector2Array([shoulder + Vector2(-5, -4), elbow + Vector2(-4, -4), wrist + Vector2(4, -3), wrist + Vector2(5, 4), shoulder + Vector2(4, 5)])
		regions["wing_upper_" + side] = _region("body", _coordinates(upper), [shoulder.x, shoulder.y], [wrist.x, wrist.y])
		regions["wing_lower_" + side] = _region("body", _coordinates(_wing_points(shoulder, base_pose, morph_id)), [wrist.x, wrist.y], [shoulder.x + pose[2].x, shoulder.y + pose[2].y])
		var hip_base: Vector2 = spec["far_hip"] if distant else spec["near_hip"]
		var hip := Vector2(hip_base.x, hip_base.y + d)
		var knee := hip + (stance[0] as Vector2) + Vector2(0, 1 if distant else 0)
		var ankle := hip + (stance[1] as Vector2)
		regions["leg_upper_" + side] = _region("body", [[hip.x - 8, hip.y - 8], [knee.x + 6, knee.y - 4], [knee.x + 6, knee.y + 6], [hip.x - 6, hip.y + 8]], [hip.x, hip.y], [knee.x, knee.y])
		regions["leg_lower_" + side] = _region("body", [[knee.x - 6, knee.y - 3], [knee.x + 6, knee.y], [ankle.x + 5, ankle.y + 2], [ankle.x - 5, ankle.y + 2]], [knee.x, knee.y], [ankle.x, ankle.y])
		regions["foot_" + side] = _region("body", [[ankle.x - 9, ankle.y - 3], [ankle.x + 13, ankle.y - 2], [ankle.x + 14, ankle.y + 9], [ankle.x - 9, ankle.y + 9]], [ankle.x, ankle.y], [ankle.x + 10, ankle.y + 4])
	var vid := "sapphire_spirewing" if (gem_id == "sapphire" and morph_id == "spirewing") else "%s_%s" % [gem_id, morph_id]
	var crop_x := maxi(0, hx - 23)
	var crop_y := maxi(0, hy - 14 + d)
	var crop_w := mini(45, 128 - crop_x)
	var crop_h := mini(38, 96 - crop_y)
	# Rider seat is placed at the base of the neck, clearly in front of the wing roots,
	# with the saddle girth wrapping around the chest just behind the forelegs.
	return {"generator": "sapphire_spirewing", "gem_id": gem_id, "morph_id": morph_id, "frame": index, "painted": true,
		"source_path": "code:%s/%d" % [vid, index], "image_size": [128, 96], "source_origin_px": [seat.x, seat.y + 3],
		"units_per_pixel": 0.48, "motion_scale": 1.0 / 12.0, "seat_px": [seat.x, seat.y + d], "seat_angle": SEAT_PITCH[index] * 0.5,
		"ground_y_px": 88, "neck_root_px": [neck_root.x, neck_root.y + d],
		"wing_roots_px": {"left": [far_wing.x, far_wing.y + d], "right": [near_wing.x, near_wing.y + d]},
		"head_crop_px": [crop_x, crop_y, crop_w, crop_h],
		"parts": {
			"body": {"label": "Body, wingbeat, hind legs and tail", "parent": "", "polygons": [[[0, 0], [128, 0], [128, 96], [0, 96]]], "pivot_px": [seat.x, seat.y + d]},
			"head": {"label": "Head and upper neck", "parent": "body", "polygons": [head], "pivot_px": [cut_x1 - 4, cut_y + 1], "ownership_priority": 1},
			"jaw": {"label": "Lower jaw", "parent": "head", "polygons": [jaw], "pivot_px": [hx, hy + 5 + d], "ownership_priority": 2}},
		"anatomical_regions": regions, "gem_regions": [], "preserve_regions": [],
		"material_masks_px": {"horns": [[[hx - 22, maxi(0, hy - 14 + d)], [hx + 4, maxi(0, hy - 14 + d)], [hx + 4, hy + 1 + d], [hx - 12, hy + 2 + d]]], "eyes": [[[hx + 2, hy - 2 + d], [hx + 5, hy - 2 + d], [hx + 5, hy + 1 + d], [hx + 2, hy + 1 + d]]]}}
