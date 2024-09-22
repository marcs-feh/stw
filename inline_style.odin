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

	inline_code := false

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
			if current == '`' {
				inline_code = !inline_code
				append(&styles, rune_to_style[current])
				append(&offsets, i)
				continue
			}

			proper_position := is_markup_rune_suitable(previous, current, next)
			if proper_position && !inline_code {
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

replace_special_html_runes :: proc(text: string) -> string {
	repl, _ := strings.replace_all(text, "<", "&lt;")
	repl, _ = strings.replace_all(repl, ">", "&gt;")
	return repl
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

unescape_markup_characters :: proc(s: string) -> string {
	to_replace :: [?]string{
		"\\*",
		"\\/",
		"\\_",
		"\\~",
		"\\`",
	}
	#assert(len(to_replace) == len(Style) - 1)

	escaped := s
	for seq in to_replace {
		escaped, _ = strings.replace_all(s, seq, seq[1:])
	}
	return escaped
}
