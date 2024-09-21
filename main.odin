package stw

import "core:mem"
import "core:fmt"
import "core:strings"

PROGRAM_MEMORY : [32 * 1024 * 1024]u8

Paragraph_Line :: struct {
	data: string,
}

Paragraph :: struct {
	lines: []string,
}

List_Item :: struct {
	lines: []string,
	level: int,
	ordered: bool,
}

Heading :: struct {
	data: string,
	level: int,
}

Code :: struct {
	lines: []string,
	language: string,
}

Line_Break :: struct {}

Block_Element :: union {
	Heading, Paragraph, List_Item, Code, Line_Break,
	Paragraph_Line,
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
		if strings.starts_with(line, "```"){
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

identation_level :: proc(s: string) -> int {
	return 100000
}

parse_blocks :: proc(lines: []string) -> []Block_Element {
	blocks := make([dynamic]Block_Element)

	parser := Line_Parser {
		lines = lines,
	}

	for !lp_done(parser) {
		line := lp_advance(&parser)
		trimmed_line := strings.trim_right(line, " \t\n\t")

		switch {
		case len(trimmed_line) == 0:
			append(&blocks, Line_Break{})

		case strings.starts_with(line, "="):
			append(&blocks, parse_heading(line))

		case strings.starts_with(line, "```"):
			parser.current -= 1
			append(&blocks, parse_code_block(&parser))

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

main :: proc(){
	source :: #load("example.txt", string)
	init_arena: {
		arena : mem.Arena
		mem.arena_init(&arena, PROGRAM_MEMORY[:])
		context.allocator = mem.arena_allocator(&arena)
	}
	defer free_all(context.allocator)

	lines, err := strings.split(source, "\n")
	if err != nil { panic("Failed allocation") }
	blocks := parse_blocks(lines)
	for b in blocks {
		fmt.println(b)
	}
	fmt.println("------------------- MERGE ---------------")
	blocks = merge_paragraph_lines(blocks)
	for b in blocks {
		fmt.println(b)
	}

}
