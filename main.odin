package stw

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

starts_with :: strings.starts_with

is_white_space :: unicode.is_white_space

PROGRAM_MEMORY : [32 * 1024 * 1024]u8

Paragraph_Line :: struct {
	data: string,
}

Paragraph :: struct {
	lines: []string,
	styled_text: []Text_Chunk,
}

List_Item :: struct {
	lines: []string,
	level: int,
	ordered: bool,
	styled_text: []Text_Chunk,
}

Heading :: struct {
	data: string,
	level: int,
	styled_text: []Text_Chunk,
}

Code :: struct {
	lines: []string,
	language: string,
	styled_text: []Text_Chunk,
}

Line_Break :: struct {}

Block_Element :: union {
	Heading, Paragraph, List_Item, Code, Line_Break,
	Paragraph_Line,
}

Style :: enum {
	Bold,
	Italic,
	Underline,
	Strikethrough,
	Code,
}

Text_Chunk :: union {
	Style,
	string,
}

Line_Parser :: struct {
	lines: []string,
	previous: int,
	current: int,
}

lp_done :: proc(parser: Line_Parser) -> bool {
	return parser.current >= len(parser.lines)
}

lp_peek :: proc(parser: Line_Parser, n: int) -> string {
	if parser.current + n >= len(parser.lines){
		return ""
	}
	return parser.lines[parser.current + n]
}

lp_advance :: proc(parser: ^Line_Parser) -> string {
	if lp_done(parser^){
		return ""
	}
	parser.current += 1
	return parser.lines[parser.current - 1]
}

count_leading_runes :: proc(s: string, key: rune) -> int {
	n := 0
	for r, i in s {
		if r != key { break }
		n += 1
	}
	return n
}

parse_heading :: proc(line: string) -> Heading {
	heading : Heading
	heading.level = count_leading_runes(line, '=')
	heading.data = line[heading.level + 1:]
	heading.data = strings.trim_space(heading.data)
	return heading
}

parse_code_block :: proc(parser: ^Line_Parser) -> Code {
	parser.previous = parser.current
	first_line := lp_advance(parser)

	for !lp_done(parser^) {
		line := lp_advance(parser)
		if starts_with(line, "```"){
			break
		}
	}

	code := Code {
		language = strings.trim_space(strings.trim_left(first_line, "`")),
		lines = parser.lines[parser.previous + 1 : parser.current - 1],
	}
	return code
}

merge_into_paragraph :: proc(blocks: []Block_Element) -> (Paragraph, int) {
	lines := make([dynamic]string)

	for block in blocks {
		if par, ok := block.(Paragraph_Line); ok {
			append(&lines, par.data)
		}
		else {
			break
		}
	}

	shrink(&lines)
	paragraph := Paragraph {
		lines = lines[:],
	}
	return paragraph, len(lines)
}

indentation_level :: proc(s: string) -> int {
	leading_spaces := 0
	leading_tabs := 0
	for r, i in s {
		if r == '\t' {
			leading_tabs += 1
			continue
		}
		if r == ' ' {
			leading_spaces += 1
			continue
		}
		break
	}

	level := (leading_spaces + (leading_tabs * 4)) / 2
	return level
}

parse_blocks :: proc(lines: []string) -> []Block_Element {
	blocks := make([dynamic]Block_Element)

	parser := Line_Parser {
		lines = lines,
	}

	for !lp_done(parser) {
		line := lp_advance(&parser)
		trimmed_line := strings.trim(line, " \t\n\t")

		switch {
		case len(trimmed_line) == 0:
			append(&blocks, Line_Break{})

		case starts_with(line, "="):
			append(&blocks, parse_heading(line))

		case starts_with(line, "```"):
			parser.current -= 1
			append(&blocks, parse_code_block(&parser))

		case starts_with(trimmed_line, "- ") || starts_with(trimmed_line, "+ "):
			parser.current -= 1
			append(&blocks, parse_list_item(&parser))

		case:
			append(&blocks, Paragraph_Line{
				data = trimmed_line,
			})
		}
	}

	shrink(&blocks)
	return blocks[:]
}

merge_paragraph_lines :: proc(blocks: []Block_Element) -> []Block_Element {
	merged_blocks := make([dynamic]Block_Element)
	for i := 0; i < len(blocks); i += 1 {
		if _, ok := blocks[i].(Paragraph_Line); ok {
			par, line_count := merge_into_paragraph(blocks[i:])
			append(&merged_blocks, par)
			i += line_count - 1
			continue
		}
		else {
			append(&merged_blocks, blocks[i])
		}
	}
	shrink(&merged_blocks)
	return merged_blocks[:]
}

is_start_of_list_item :: proc(s: string) -> (which: rune, ok: bool) {
	if starts_with(strings.trim_left_space(s), "- "){ return '-', true }
	if starts_with(strings.trim_left_space(s), "+ "){ return '+', true }
	return 0, false
}

parse_list_item :: proc(parser: ^Line_Parser) -> List_Item {
	parser.previous = parser.current
	lines := make([dynamic]string)

	first_line := lp_advance(parser)
	first_indent := indentation_level(first_line)

	append(&lines, strings.trim_space(first_line)[2:])

	kind, ok := is_start_of_list_item(first_line)
	assert(ok, "First line must be of list prefix")

	for !lp_done(parser^){
		line := lp_peek(parser^, 0)
		if _, ok := is_start_of_list_item(line); ok{
			break
		}
		else if starts_with(strings.trim_left(line, "\t"), "  "){
			level := indentation_level(line)
			if level - 1 == first_indent {
				append(&lines, strings.trim_space(line))
				parser.current += 1
			}
			else {
				break
			}
		}
		else {
			break
		}
	}

	shrink(&lines)
	item := List_Item {
		lines = lines[:],
		level = first_indent,
		ordered = kind == '+',
	}
	return item
}

Style_Parser :: struct {
	current: int,
	previous: int,
	source: string,
}

join_lines :: proc(blocks: []Block_Element) -> (err: mem.Allocator_Error) {
	for &block, i in blocks {
		switch &block in block {
		case Paragraph:
			joined := strings.join(block.lines, "\n") or_return
			block.lines[0] = joined
			block.lines = block.lines[:1]
		case List_Item:
			joined := strings.join(block.lines, "\n") or_return
			block.lines[0] = joined
			block.lines = block.lines[:1]
		case Code:
			joined := strings.join(block.lines, "\n") or_return
			block.lines[0] = joined
			block.lines = block.lines[:1]

		case Paragraph_Line, Line_Break, Heading:
		}
	}
	return
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

parse_style :: proc(source: string){
	previous := '\n'
	next : rune
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

		if is_markup_rune(current) && previous != '\\' {
			proper_position := is_markup_rune_suitable(previous, current, next)
			if proper_position {
				fmt.println("OK: ", current, i)
			}
		}
	}
}

main :: proc(){
	source :: #load("example.txt", string)
	init_arena: {
		arena : mem.Arena
		mem.arena_init(&arena, PROGRAM_MEMORY[:])
		context.allocator = mem.arena_allocator(&arena)
	}
	defer free_all(context.allocator)

	s :: "/*_italic_*/ and\\/_or_ https://hello.com/cu/article/100"
	parse_style(s)

	// lines, err := strings.split(source, "\n")
	// if err != nil { panic("Failed allocation") }
	// blocks := parse_blocks(lines)
	// for b in blocks {
	// 	fmt.println(b)
	// }
	// fmt.println("------------------- MERGE ---------------")
	// blocks = merge_paragraph_lines(blocks)
	// join_err := join_lines(blocks)
	// assert(join_err == nil)
	//
	// for b in blocks {
	// 	fmt.println(b)
	// }
}
