package home

import "chain/runtime/unsafe"

// admin is the only address allowed to mutate the dashboard state.
const admin = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

var (
	todos      []string
	status     string
	memeImgURL string
)

func init() {
	todos = append(todos, "fill this todo list...")
	status = "Online" // Initial status set to "Online"
	memeImgURL = "https://i.imgflip.com/7ze8dc.jpg"
}

func assertIsAdmin() {
	if unsafe.PreviousRealm().Address() != admin {
		panic("restricted to admin")
	}
}

func Render(path string) string {
	content := "# Manfred's (gn)home Dashboard\n\n"

	content += "## Meme\n"
	content += "![](" + memeImgURL + ")\n\n"

	content += "## Status\n"
	content += status + "\n\n"

	content += "## Personal ToDo List\n"
	for _, todo := range todos {
		content += "- [ ] " + todo + "\n"
	}
	content += "\n"

	// TODO: Implement a feature to list replies on r/boards on my posts
	// TODO: Maybe integrate a calendar feature for upcoming events?

	return content
}

func AddNewTodo(cur realm, todo string) {
	assertIsAdmin()
	todos = append(todos, todo)
}

func DeleteTodo(cur realm, todoIndex int) {
	assertIsAdmin()
	if todoIndex >= 0 && todoIndex < len(todos) {
		// Remove the todo from the list by merging slices from before and after the todo
		todos = append(todos[:todoIndex], todos[todoIndex+1:]...)
	} else {
		panic("Invalid todo index")
	}
}

func UpdateStatus(cur realm, newStatus string) {
	assertIsAdmin()
	status = newStatus
}
