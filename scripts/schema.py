import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def obj(props,required):return {'type':'object','properties':props,'required':required,'additionalProperties':False}
string={'type':'string','minLength':1};ident={'type':'string','pattern':'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'};strings={'type':'array','items':string}
def arr(x):return {'type':'array','items':x}
ref={'$ref':'#/$defs/reference'}
base={'id':ident,'type':string,'references':arr(ref),'extensions':{'type':'object'}}
blocks={
'markdown':({'file':string,'role':{'const':'takeaway'},'visibility':{'enum':['visible','contextOnly']}},['file']),
'code':({'language':string,'code':string},['language','code']),
'table':({'columns':strings,'rows':arr(arr({'type':'string'}))},['columns','rows']),
'image':({'file':string,'alt':string,'description':string},['file','alt','description']),
'diagram':({'layout':{'enum':['flow','routes','sparse']},'title':string,'captionMarkdown':string,'nodes':arr(obj({'kicker':string,'title':string,'detailMarkdown':string,'dark':{'type':'boolean'}},['kicker','title','detailMarkdown'])),'routes':arr(obj({'label':string,'nodes':strings},['label','nodes'])),'segments':arr(obj({'text':string,'range':string},['text','range'])),'metrics':arr(obj({'label':string,'value':string},['label','value']))},['layout']),
'math':({'latex':string,'description':string},['latex','description']),
'singleChoice':({'question':string,'options':{'type':'array','minItems':2,'maxItems':12,'items':obj({'id':ident,'text':string},['id','text'])},'answerId':ident,'explanation':string,'revisit':ident},['question','options','answerId','explanation']),
'reveal':({'prompt':string,'answerMarkdown':string},['prompt','answerMarkdown']),
'steps':({'presentation':{'enum':['program','explanation']},'initialState':{'type':'boolean'},'steps':{'type':'array','minItems':1,'items':obj({'id':ident,'title':string,'bodyMarkdown':string,'code':string,'snapshot':{'type':'object'}},['id','title','bodyMarkdown'])}},['steps']),
'filePosition':({'initialText':{'type':'string'},'maxOffset':{'type':'integer','minimum':1,'maximum':1000}},['initialText','maxOffset']),
'callCount':({'initialBuffer':{'type':'integer','minimum':1},'bytes':{'type':'integer','minimum':1},'buffers':{'type':'array','minItems':1,'items':{'type':'integer','minimum':1}}},['bytes','buffers'])}
blockdefs=[]
for kind,(props,required) in blocks.items():blockdefs.append(obj({**base,'type':{'const':kind},**props},['id','type',*required]))
source=obj({'id':ident,'title':string,'kind':{'enum':['pdf','text','web','reference']},'file':string,'url':{'type':'string','pattern':'^https://'},'extensions':{'type':'object'}},['id','title','kind'])
reference=obj({'sourceId':ident,'locator':obj({'kind':{'enum':['pdfPage','printedPage','section','lineRange','timeRange','unknown']},'value':{'type':['string','integer','array']}},['kind','value'])},['sourceId'])
course=obj({'schemaVersion':{'enum':['1.0','1.1']},'courseId':ident,'contentVersion':{'type':'string','pattern':'^\\d+\\.\\d+\\.\\d+$'},'title':string,'language':string,'audience':{'type':'string'},'scopes':arr(obj({'id':ident,'title':string},['id','title'])),'archiveFiles':arr(obj({'file':string,'title':string},['file','title'])),'objectives':strings,'modules':{'type':'array','minItems':1,'items':obj({'id':ident,'title':string,'topics':{'type':'array','minItems':1,'items':ident}},['id','title','topics'])},'topics':{'type':'array','minItems':1,'maxItems':2000,'items':obj({'id':ident,'file':string},['id','file'])},'sources':arr(source),'extensions':{'type':'object'}},['schemaVersion','courseId','contentVersion','title','language','modules','topics'])
topic=obj({'id':ident,'title':string,'lead':string,'focus':string,'scope':ident,'estimatedMinutes':{'type':'number','exclusiveMinimum':0},'assessment':{'type':'boolean'},'backTo':ident,'objectives':strings,'prerequisites':arr(ident),'blocks':{'type':'array','minItems':1,'maxItems':300,'items':{'oneOf':blockdefs}},'extensions':{'type':'object'}},['id','title','blocks'])
for name,s in [('course',course),('topic',topic)]:s.update({'$schema':'https://json-schema.org/draft/2020-12/schema','$defs':{'reference':reference}});(ROOT/'protocol'/f'{name}.schema.json').write_text(json.dumps(s,ensure_ascii=False,indent=2))
