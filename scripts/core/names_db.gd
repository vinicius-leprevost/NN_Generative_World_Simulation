extends Node
## Names: procedural name generation for people and groups.

const FIRST_M := ["Adan", "Bram", "Cato", "Dov", "Eron", "Finn", "Garen", "Hale",
	"Ilan", "Joren", "Kai", "Lior", "Mavo", "Nils", "Oren", "Pavel", "Quinn",
	"Ravi", "Soren", "Tavor", "Ulric", "Varen", "Wade", "Yaro", "Zane"]
const FIRST_F := ["Ana", "Brena", "Cara", "Dena", "Eira", "Fara", "Gala", "Hana",
	"Ivy", "Juna", "Kira", "Lena", "Mira", "Nia", "Ona", "Petra", "Rhea",
	"Sena", "Tala", "Una", "Vera", "Wren", "Yara", "Zola"]
const LAST := ["Ash", "Brook", "Clay", "Dale", "Elm", "Fern", "Glen", "Hollow",
	"Iron", "Kettle", "Lake", "Moss", "North", "Oak", "Pine", "Reed", "Stone",
	"Thorn", "Vale", "Wold", "Wren", "Yew"]
const GROUP_A := ["River", "Stone", "Sun", "Moon", "Ash", "Iron", "Green", "Red",
	"Silent", "Swift", "North", "Deep", "Wild", "First", "Old"]
const GROUP_B := ["Circle", "Kin", "Band", "Hands", "Walkers", "Keepers", "Folk",
	"Union", "Watch", "Pact", "Voices", "Builders", "Hunters"]

func person_name(sex: String) -> String:
	var first: String
	if sex == "f":
		first = Rng.pick(FIRST_F)
	else:
		first = Rng.pick(FIRST_M)
	return "%s %s" % [first, Rng.pick(LAST)]

func group_name() -> String:
	return "%s %s" % [Rng.pick(GROUP_A), Rng.pick(GROUP_B)]
