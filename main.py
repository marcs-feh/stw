from dataclasses import dataclass, field

PARAGRAPH  = 'paragraph'
HEADING    = 'heading'
CODE       = 'code'
LINE_BREAK = 'line_break'
LIST_ITEM  = 'list_item'
# CITATION = 'citation'

@dataclass
class Block:
    kind : str = PARAGRAPH
    data : str = ''
    styled_data : list = field(default_factory=list)
    level : int = 0
    language : str | None = None
    ordered_list : bool = False

    def __repr__(self):
        if self.kind == HEADING:
            return f'{self.kind}({self.level}): {self.data}'
        elif self.kind == CODE:
            return f'{self.kind}({self.language}): {self.data}'
        elif self.kind == LIST_ITEM:
            return f'{self.kind}({self.level}{" N" if self.ordered_list else ""}): {self.data}'
        else:
            return f'{self.kind}: {self.data}'

def consume_code_lines(lines: list[str], start: int) -> list[str]:
    code = []
    for line in lines[start:]:
        if line.startswith('```'):
            break
        code.append(line)
    return code

def parse_heading(line: str):
    n = 0
    for c in line:
        if c != '=': break
        n += 1
    return Block(HEADING, line[n:].strip(), level=n)

def indent_level(s: str):
    s = s.replace('\t', '    ')
    leading_spaces = len(s) - len(s.lstrip(' '))
    return leading_spaces // 2

def start_of_list_item(s: str) -> str | None:
    if s.strip().startswith('+ '): return '+'
    if s.strip().startswith('- '): return '-'
    return None

def parse_list_item(lines: list[str], start: int):
    prefix = start_of_list_item(lines[start])
    assert prefix
    item_lines = [lines[start].replace(f'{prefix} ', '', 1)]
    first_indent = indent_level(lines[start])

    for line in lines[start + 1:]:
        if start_of_list_item(line):
            break
        elif line.strip('\t').startswith('  '):
            level = indent_level(line)
            if (level - 1) == first_indent:
                item_lines.append(line.lstrip())
            else:
                break
        else:
            break

    return (item_lines, first_indent, prefix == '+')

def merge_paragraphs(blocks: list[Block]):
    merged = [Block(LINE_BREAK)]
    for b in blocks:
        if b.kind == PARAGRAPH and merged[-1].kind == PARAGRAPH:
            merged[-1].data += '\n' + b.data
        else:
            merged.append(b)
    return merged

def parse_blocks(lines) -> list[Block]:
    blocks = []
    i = 0

    while i < len(lines):
        line = lines[i].rstrip()
        if len(line) == 0:
            blocks.append(Block(LINE_BREAK))
        elif line.startswith('='):
            blocks.append(parse_heading(line))
        elif line.startswith('```'):
            language = line.lstrip('```')
            code_lines = consume_code_lines(lines, i + 1)
            blocks.append(Block(CODE, ''.join(code_lines), language=language))
            i = i + len(code_lines) + 2
            continue
        elif start_of_list_item(line):
            item_lines, level, ordered = parse_list_item(lines, i)
            blocks.append(Block(LIST_ITEM, ''.join(item_lines), level=level, ordered_list=ordered))
            i = i + len(item_lines)
            continue
        else:
            blocks.append(Block(PARAGRAPH, line))

        i += 1

    return merge_paragraphs(blocks)

ITALIC      = 'italic'
BOLD        = 'bold'
STRIKETHRU  = 'strikethrough'
UNDERLINE   = 'underline'
INLINE_CODE = 'code'

@dataclass
class TextEffect:
    kind: str

def is_surrounded_by_whitespace(s: str, c: int) -> bool:
    surroundings = s[c - 1:c + 2]
    return len(surroundings.strip()) == 1

# TODO: Handle escaping the effects with '\'
def parse_inline_effects(b: Block) -> list:
    content = []
    previous = 0
    effects = {
        '*': TextEffect(BOLD),
        '/': TextEffect(ITALIC),
        '~': TextEffect(STRIKETHRU),
        '_': TextEffect(UNDERLINE),
    }

    i, c = 0, 0
    in_code = False
    for i, c in enumerate(b.data):
        if c == '`':
            content.append(b.data[previous:i])
            previous = i + 1
            in_code = not in_code
        if in_code: continue

        if not is_surrounded_by_whitespace(b.data, i):
            if c in effects:
                acc = b.data[previous:i]
                previous = i + 1
                content.append(acc)
                content.append(effects[c])
    content.append(b.data[previous:])
    return content

def render_inline_style(block_data: list) -> str:
    html = ''
    effect_state = {
        ITALIC: False,
        BOLD: False,
        STRIKETHRU: False,
        UNDERLINE: False,
    }

    TAG_MAP = {
        ITALIC: 'i',
        BOLD: 'b',
        STRIKETHRU: 's',
        UNDERLINE: 'u',
    }

    for data in block_data:
        if type(data) is str:
            html += data.replace('\n', ' ')
        elif type(data) is TextEffect:
            slash = '/' if effect_state[data.kind] else ''
            effect_state[data.kind] = not effect_state[data.kind]
            html += f'<{slash}{TAG_MAP[data.kind]}>'

    return html

def render_html(blocks: list[Block]) -> str:
    html = ''

    for block in blocks:
        if block.kind == PARAGRAPH:
            html += '<p>'
            html += render_inline_style(block.styled_data)
            html += '</p>\n'

    return html

with open('example.txt', 'r') as f:
    data = f.readlines()

blocks = parse_blocks(data)
for block in blocks:
    if block.kind in (PARAGRAPH, LIST_ITEM):
        block.styled_data = parse_inline_effects(block)
    print(block.styled_data)

print(render_html(blocks))
