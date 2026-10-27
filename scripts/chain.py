import re, sys, json, urllib.parse, random
raw = open(sys.argv[1], 'r', encoding='utf-8', errors='ignore').read()
m = re.search(r"(a=')(.+?)(',JSON\.parse)", raw)
enc = m.group(2)
cfg = json.loads(urllib.parse.unquote(enc))
val = cfg['form']['values']
keys = list(val.keys()); random.shuffle(keys)
screen = {'sw1':'-1','sw2':'1920','sh2':'1080','sw3':'1858','sh3':'951',
          'sw4':'1858','sh4':'951','sw5':'1920','sh5':'1080','sw6':'1920',
          'sh6':'1080','sw7':'1858','sh7':'945','fr':'0'}
pairs = screen.items() if False else list(screen.items())
allkeys = list(screen.keys()) + keys; random.shuffle(allkeys)
merged = dict(screen); merged.update(val)
print('&'.join(f'{k}={urllib.parse.quote(merged[k])}' for k in allkeys))
print('ACTION=' + cfg['form']['action'], file=sys.stderr)
