
class Article:
    def __init__(self):
        self.title = ''
        self.author = ''
        self.text_content = ''

    def to_html(self):
        return 'hi'

art = Article()
print(art.author)
