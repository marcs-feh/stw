package stw

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

normalize_list_items :: proc(blocks: []Block_Element){}

main :: proc(){
	source :: #load("example.txt", string)
	init_arena: {
		arena : mem.Arena
		mem.arena_init(&arena, PROGRAM_MEMORY[:])
		context.allocator = mem.arena_allocator(&arena)
	}
	defer free_all(context.allocator)

	s := "*this* should recieve markup but `*this* >right< \\`here\\`` should not"
	s = replace_special_html_runes(s)

	tbl := parse_style(s)
	html := style_to_html(s, tbl)
	html = unescape_markup_characters(html)
	fmt.println(html)
}
