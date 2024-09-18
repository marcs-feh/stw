
# Opcodes for the "text machine"
TEXT        = 'text'
BOLD        = 'bold'
ITALIC      = 'italic'
STRIKETHRU  = 'strikethrough'
UNDERLINE   = 'underline'
CODE_INLINE = 'code'
CODE_BLOCK  = 'code block'
PAR_BREAK   = 'paragraph break'

class TextCommand:
    def __init__(self, kind = TEXT, data = 0):
        self.kind : str = kind
        self.data : str | int = data

    def __repr__(self) -> str:
        s = f'{self.kind}'
        if self.kind == TEXT:
            s = f'{chr(self.data)}'
        return s

def is_space(s: str) -> bool:
    assert len(s) <= 1
    return s in ('\t', '\r', '\v', ' ')

def tokenize_markup(src: str) -> list[TextCommand]:
    current = 0
    commands = []

    def peek(n: int):
        if current + n >= len(src) or current + n < 0:
            return ''
        return src[current + n]

    def match_styling(c: str, expect: str, kind: str) -> bool:
        matched = False
        if c == expect and not is_space(peek(1)) and peek(-1) != '\\':
            matched = True
            commands.append(TextCommand(kind))
        return matched

    for i, c in enumerate(src):
        if current > i: continue
        current = i

        if match_styling(c, '*', BOLD): continue
        if match_styling(c, '/', ITALIC): continue
        if match_styling(c, '_', UNDERLINE): continue
        if match_styling(c, '~', STRIKETHRU): continue
        if match_styling(c, '`', CODE_INLINE): continue

        if c == '\n' and peek(-1) == '\n':
            current += 1
            commands.append(TextCommand(PAR_BREAK))
        else:
            commands.append(TextCommand(TEXT, ord(c)))

    return commands

class TextMachine:
    def __init__(self):
        self.instructions = list()
        self.buf : str = ''

    def load(self, instructions):
        self.instructions = instructions
        self.buf = ''

    def run(self) -> str:
        return

with open('example.txt', 'r') as f:
    data = f.read()
    print(tokenize_markup(data))

