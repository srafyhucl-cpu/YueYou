import sys

files = [
    'test/features/reader/teleprompter_view_test.dart',
    'test/features/reader/chapter_list_screen_test.dart',
    'test/features/game_2048/square_board_test.dart'
]

for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        c = file.read()
    c = c.replace('reader.dispose();', '')
    c = c.replace('service.dispose();', '')
    c = c.replace('reader.ttsEngine.dispose();', '')
    c = c.replace('addTearDown(provider.dispose);', '')
    with open(f, 'w', encoding='utf-8') as file:
        file.write(c)
