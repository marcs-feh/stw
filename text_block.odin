package stw

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

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

	post_process: {
		post_blocks := merge_paragraph_lines(blocks[:])
		join_block_lines(post_blocks)
		delete(blocks)
		return post_blocks
	}
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

	item := List_Item {
		lines = lines[:],
		level = first_indent,
		ordered = kind == '+',
	}
	return item
}

join_block_lines :: proc(blocks: []Block_Element) -> (err: mem.Allocator_Error) {
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

