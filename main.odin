package stw

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

starts_with :: strings.starts_with

is_white_space :: unicode.is_white_space

PROGRAM_MEMORY : [48 * 1024 * 1024]u8

Style :: enum i8 {
	None = 0,
	Bold,
	Italic,
	Underline,
	Strikethrough,
	Code,
}

rune_to_style :: []Style{
	'*' = .Bold,
	'/' = .Italic,
	'~' = .Strikethrough,
	'`' = .Code,
	'_' = .Underline,
}

Style_Parser :: struct {
	current: int,
	previous: int,
	source: string,
}

sp_done :: proc(parser: Style_Parser) -> bool {
	return parser.current >= len(parser.source)
}

sp_advance :: proc(parser: ^Style_Parser) -> (rune, int) {
	if sp_done(parser^){
		return 0, 0
	}
	r, n := utf8.decode_rune(parser.source[parser.current:])
	parser.current += n
	return r, n
}

is_markup_rune :: proc(r: rune) -> bool {
	switch r {
	case '*', '/', '~', '_', '`':
		return true
	case:
		return false
	}
}

// A markup rune (R) is interpreted as markup if it is in the following form
// W := word rune, non-whitespace
// M := another markup rune distinct from R
// S := whitespace
// Suitable(R) := ((S|M)R(W|M)) | ((W|M)R(S|M))
is_markup_rune_suitable :: proc(prev, cur, next: rune) -> bool {
	assert(is_markup_rune(cur), "Middle rune must be a valid markup rune")

	markup :: proc(r: rune, unless: rune) -> bool {
		return is_markup_rune(r) && r != unless
	}
	word :: proc(r: rune) -> bool {
		return !is_markup_rune(r) && !is_white_space(r)
	}
	space_or_markup :: proc(r: rune, unless: rune) -> bool {
		return is_white_space(r) || markup(r, unless)
	}
	word_or_markup :: proc(r: rune, unless: rune) -> bool {
		return word(r) || markup(r, unless)
	}

	c1 := space_or_markup(prev, cur) && word_or_markup(next, cur)
	c2 := word_or_markup(prev, cur) && space_or_markup(next, cur)

	return c1 || c2
}

Style_Table :: struct {
	offsets: []int,
	styles: []Style,
}

parse_style :: proc(source: string) -> Style_Table {
	sb : strings.Builder
	previous := '\n'
	next : rune
	rune_to_style := rune_to_style

	offsets := make([dynamic]int)
	styles := make([dynamic]Style)

	// TODO: handle code
	for current, i in source {
		defer previous = current
		get_next_rune: {
			next_rune_offset := i + utf8.rune_size(current)
			if next_rune_offset >= len(source) {
				next = '\n'
			} else {
				next, _ = utf8.decode_rune(source[next_rune_offset:])
			}
		}

		// TODO: escaping
		if is_markup_rune(current) && previous != '\\' {
			proper_position := is_markup_rune_suitable(previous, current, next)
			if proper_position {
				append(&styles, rune_to_style[current])
				append(&offsets, i)
			}
		}
	}

	return Style_Table {
		offsets = offsets[:],
		styles = styles[:],
	}
}

style_to_html_tag :: [Style]string {
	.None = "?",
	.Bold = "b",
	.Italic = "i",
	.Underline = "u",
	.Strikethrough = "s",
	.Code = "code",
}

style_to_html :: proc(text: string, table: Style_Table) -> string {
	sb : strings.Builder
	strings.builder_init(&sb, 0, len(text) + len(table.offsets) * 4)
	state : #sparse [Style]bool
	style_to_html_tag := style_to_html_tag

	prev_offset := -1
	for i in 0..<len(table.offsets) {
		style, offset := table.styles[i], table.offsets[i]
		defer prev_offset = offset
		state[style] = !state[style]

		fmt.sbprintf(&sb, "%s<%s%s>",
			text[prev_offset + 1:offset],
			state[style] ? "" : "/",
			style_to_html_tag[style])
	}
	fmt.sbprintf(&sb, "%s\n", text[prev_offset + 1:])

	return string(sb.buf[:])
}

main :: proc(){
	source :: #load("example.txt", string)
	init_arena: {
		arena : mem.Arena
		mem.arena_init(&arena, PROGRAM_MEMORY[:])
		context.allocator = mem.arena_allocator(&arena)
	}
	defer free_all(context.allocator)

	s := "/*_italic_*/ and\\/_or_ >>https://hello.com/cu/article/100<< with `code` and all"

	tbl := parse_style(s)
	html := style_to_html(s, tbl)
	fmt.println(html)

}
