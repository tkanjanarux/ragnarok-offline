"""Read-only portfolio planner and telemetry decoder for staged Basilisk parties."""
from collections import Counter, defaultdict, deque
from functools import lru_cache
import gzip
import heapq
import json
import math
from pathlib import Path
import re
import struct
import sys
import time
import zlib

OWNER=2000001
P,K,W,H=range(95000000,95000004)
CAMP=95000004
TEAM=(OWNER,P,K,W,H)
ALIASES=('Knight','Priest','Wizard','Hunter')
RX=re.compile(r'\bB_([A-Z]+) (.*)')
FRAME={'PARTY','AID','MOVE','PULLSTATE','ELIG','A','M','COVER','PACK','PEER','SK','SUPPLY','BUFF','CD'}
def dist(a,b):return max(abs(a[0]-b[0]),abs(a[1]-b[1]))
def pos(a):return tuple(a[4:6])
def readlog(path,live):
    deadline=time.monotonic()+180
    while not path.exists():
        if time.monotonic()>deadline:raise TimeoutError(path)
        time.sleep(.1)
    with (gzip.open(path,'rt',errors='replace') if path.suffix=='.gz' else path.open(errors='replace')) as f:
        partial=''
        while True:
            line=f.readline()
            if not line:
                if not live:return
                if time.monotonic()>deadline:raise TimeoutError('no log data')
                time.sleep(.04)
                continue
            deadline=time.monotonic()+180
            if live and not line.endswith('\n'):
                partial+=line
                continue
            yield partial+line
            partial='' 

@lru_cache(None)
def terrain(name):
    root=Path('companion-dev/runtime/m94/db')
    for p in ('import/map_cache.dat','re/map_cache.dat','map_cache.dat'):
        b=(root/p).read_bytes()
        i=8
        while i<len(b):
            key,w,h,n=struct.unpack_from('<12shhi',b,i)
            i+=20
            if key.split(b'\0')[0].decode()==name:return w,h,zlib.decompress(b[i:i+n])
            i+=n
    raise KeyError(name)

class World:
    def __init__(self):
        self.hits=deque();self.pending_heal={};self.fields={};self.cells=defaultdict(set);self.peels={}
        self.five=False;self.direct_spells=False;self.spell=None;self.frame=None;self.active=False;self.interrupt_until=0

    def frames(self,lines):
        for line in lines:
            match=RX.search(line)
            if not match:continue
            k,data=match.groups()
            if k=='BOUND' and data.strip()=='start':
                self.active=True
                continue
            if not self.active:continue
            if k=='MARK' and data.startswith('end'):break
            if self.frame is not None and k not in FRAME:
                f,self.frame=self.frame,None
                if CAMP in f['a']:self.five=True
                roster=(*TEAM,CAMP) if self.five else TEAM
                f['healer']=CAMP if self.five else P
                if self.five:f['cover']=f['aid'].get(CAMP,{})
                if all(t in f['a'] and t in f['cover'] for t in roster):yield 'frame',f
            if k in ('MARK','BOUND'):continue
            try:v=list(map(int,data.split()))
            except ValueError:continue
            if k=='AGGRO':
                if v[2]==W and v[3]==K:self.peels[v[1]]=v[0]
                else:self.peels.pop(v[1],None)
            if k=='KILL':self.peels.pop(v[1],None)
            if k=='FRAME':
                self.frame=dict(t=v[0],anchor=tuple(v[3:5]),cap=v[6],pull=P if v[7] else K,inbound=v[8],release=v[9],a={},m={},cover={},pack=set(),peer=[],sk={},supply={},buff={},elig={},cd={},motion={},aid={},party={},peels=self.peels.copy(),native_target=None)
            f=self.frame
            if f is not None:
                if k=='AID':
                    self.direct_spells=True
                    f['aid'].setdefault(v[1],{})[v[2]]=v[3:]
                elif k=='PARTY':f['party'][v[1]]=v[2:]
                elif k=='MOVE':f['motion'][v[1]]=v[2:]
                elif k=='PULLSTATE':f['native_target']=v[1] if not(v[2] or v[3]) else 0
                elif k=='ELIG':f['elig'][v[1]]=v[2:]
                elif k=='A':f['a'][v[1]]=v
                elif k=='M':f['m'][v[1]]=v
                elif k=='COVER':f['cover'][v[1]]=v[2:7]
                elif k=='PACK':f['pack'].add(v[1])
                elif k=='PEER':f['peer'].append(tuple(v[2:4]))
                elif k=='CD':f['cd'][v[1],v[2]]=v[3]
                elif k=='SK':f['sk'][v[1],v[2]]=v[3:]
                elif k=='SUPPLY':f['supply'][v[1],v[2]]=v[3]
                elif k=='BUFF':f['buff'][v[1],v[2]]=v[3:]
            if k=='HIT' and v[4]>0:
                self.hits.append(v)
                while self.hits and self.hits[0][0]<v[0]-10000:self.hits.popleft()
            if k=='CANCEL' and v[1:3]==[W,89]:self.interrupt_until=v[0]+3500
            if k=='SPELL':self.spell=v
            if k=='DELIVER':self.spell=None
            if k=='HEAL' and v[2]>0 and self.spell and self.spell[1] in (P,CAMP) and self.spell[2:]==[v[1],28]:
                self.pending_heal.pop(v[1],None)
                yield 'effect',v
            if k=='CAST' and not self.direct_spells and v[1]==P and v[2]==28:self.pending_heal[v[4]]=v[0]+v[7]
            if k=='HEAL' and v[2]>0 and 0<=v[0]-self.pending_heal.get(v[1],-10**15)<=2:
                self.pending_heal.pop(v[1])
                yield 'effect',v
            if k=='HEAL' and v[2]>0:yield 'restore',v
            if k=='PULL':yield 'pull',v
            if k=='CELL':self.cells[v[1]].add(tuple(v[2:4]))
            if k=='FIELD':self.fields[v[1]]=v
            if k=='END':
                self.fields.pop(v[1],None);self.cells.pop(v[1],None)
            if k in ('HIT','CAST','CANCEL','AGGRO','DEATH','BREAK','INTERRUPT','KILL'):yield k,v

def base_eta(f,actor):
    healer=f['a'][f.get('healer',P)]; target=f['a'][actor]
    reach,enabled,sp,idle,ready=f['cover'][actor]
    gap=dist(pos(healer),pos(target))
    wait=max(0,healer[17]-f['t'],healer[18]-f['t'])/1000
    travel=0 if reach else max(1,gap-8)*healer[20]/1000*1.6
    fraction=target[6]/max(1,target[7])
    queued=sum(0<a[6]/max(1,a[7])<min(.70,fraction) for i,a in f['a'].items() if i!=actor and f['cover'][i][0])
    # A threatened helper loses action opportunities while recovering from hits.
    # Use the same causal adjustment in calibration and live prediction.
    attackers=sum(m[5]==P and dist(m[3:5],pos(healer))<=m[11]+1 for m in f['m'].values())
    interruption_delay=min(3,attackers)*.65
    return max(travel,wait)+1.2*queued+interruption_delay+(.8 if not idle else .4),('near' if reach else 'far')

def partition(f,actor):
    eta,reach=base_eta(f,actor)
    return eta,('priest' if f['pull']==P else 'knight')+'-'+reach

class Influence:
    def __init__(self,f,w):
        self.f=f;self.w=w
        self.map=terrain({448:'yuno_fild07',450:'yuno_fild09'}[f['a'][OWNER][3]])
        self.local=[m for m in f['m'].values() if dist(m[3:5],f['anchor'])<=104 and m[6]>0 and not 1078<=m[2]<=1085]
        self.hostile=set().union(*(w.cells[g] for g,v in w.fields.items() if v[2] not in self.f['a'] and v[0]+v[7]>f['t']))
        self.memo={}
        self.pressure=Counter()
        for v in w.hits:
            if v[0]>=f['t']-8000 and v[2] in self.f['a']:self.pressure[v[1]]+=v[4]/8
    def open(self,p):
        x,y=p;w,h,c=self.map
        return 0<=x<w and 0<=y<h and c[y*w+x] in (0,2,3,4,6)
    def risk(self,p,arrival=0):
        # Exposure at nominal arrival, including expiry of hostile ground fields.
        horizon=1 if arrival<=2 else 4 if arrival<=5 else 8
        key=p,horizon
        if key not in self.memo:
            pressure=0.
            for m in self.local:
                here=tuple(m[3:5]);target=self.f['a'].get(m[5])
                if dist(here,p)>18 and not target:continue
                if target and not m[12]:
                    dest=pos(target);gap=max(1,dist(here,dest))
                    steps=min(gap,1000*horizon/max(100,m[8]))
                    here=tuple(round(x+(y-x)*steps/gap) for x,y in zip(here,dest))
                damage=1+min(3,self.pressure[m[1]]/120)
                pressure+=max(0,1-max(0,dist(p,here)-m[11])/6)*damage*(1 if target else .35)*(.2 if m[12] and horizon==1 else 1)
            for group,v in self.w.fields.items():
                if v[2] not in self.f['a'] and v[0]+v[7]>self.f['t']+1000*horizon and p in self.w.cells[group]:pressure+=8
            self.memo[key]=pressure
        return self.memo[key]
    def blocked(self,p):
        return not self.open(p) or p in self.hostile or any(dist(p,q)<=4 for q in self.f['peer'])
    def route(self,start,goal):
        # Bounded A* on walkable cells. Unknown/unreachable routes grant no pull.
        todo=[(dist(start,goal),0,start)]
        cost={start:0};parent={}
        while todo and len(cost)<500:
            _,g,p=heapq.heappop(todo)
            if g!=cost[p]:continue
            if p==goal:
                path=[]
                while p!=start:path.append(p);p=parent[p]
                return path[::-1]
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
                q=p[0]+dx,p[1]+dy
                if self.blocked(q) or not self.open((q[0],p[1])) or not self.open((p[0],q[1])):continue
                ng=g+1+.15*self.risk(q,dist(start,q)*self.f['a'][self.f['pull']][20]/1000)
                if ng<cost.get(q,1e9):
                    cost[q]=ng;parent[q]=p;heapq.heappush(todo,(ng+dist(q,goal),ng,q))
        return []

def needs_heal(actor):
    return 0 < actor[6]*100 < actor[7]*70

@lru_cache(maxsize=32768)
def attack_distance(name,start,goal,reach,max_steps):
    """Shortest walk to a legal firing cell, in tenths of a cardinal step."""
    width,height,cells=terrain(name)
    def walk(x,y):
        return 0<=x<width and 0<=y<height and cells[y*width+x] in (0,2,3,4,6)
    def heuristic(p):
        dx=max(0,abs(p[0]-goal[0])-reach);dy=max(0,abs(p[1]-goal[1])-reach)
        return 10*max(dx,dy)+4*min(dx,dy)
    def visible(p):
        n=dist(p,goal)
        return all(walk(round(p[0]+(goal[0]-p[0])*k/n),round(p[1]+(goal[1]-p[1])*k/n)) for k in range(1,n))
    limit=max_steps*10
    costs={start:0};todo=[(heuristic(start),0,start)]
    while todo:
        lower,g,cell=heapq.heappop(todo)
        if lower>limit:break
        if costs[cell]!=g:continue
        if dist(cell,goal)<=reach and visible(cell):return g/10
        x,y=cell
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
            q=x+dx,y+dy
            if not walk(*q) or not walk(x+dx,y) or not walk(x,y+dy):continue
            ng=g+(14 if dx and dy else 10)
            if ng<costs.get(q,limit+1):
                costs[q]=ng;heapq.heappush(todo,(ng+heuristic(q),ng,q))
    return math.inf

def reachable_wave(f,actor,horizon):
    ally=f['a'][actor];target=pos(ally);knight=f['a'][K]
    name={448:'yuno_fild07',450:'yuno_fild09'}[ally[3]]
    arrivals=[]
    for mid,m in f['m'].items():
        if not m[6] or 1078<=m[2]<=1085:continue
        cell=tuple(m[3:5]);gap=dist(cell,target);attack_range=max(1,m[11])
        speed=max(.05,m[8]/1000)
        if (gap-attack_range)*speed>horizon:continue
        aggressive,sight,thaw=f['motion'].get(mid,(True,9,0))
        if m[5]!=actor:
            if m[5]:
                # A change from a live victim needs proximity or a crossing.
                victim=f['a'].get(m[5])
                if not victim:continue
                here=pos(victim);dest=tuple(victim[10:12]) if victim[12] else here
                n=max(1,dist(here,dest))
                crossing=any(dist((round(here[0]+(dest[0]-here[0])*j/n),round(here[1]+(dest[1]-here[1])*j/n)),target)<=attack_range+2 for j in range(n+1))
                if gap>attack_range+2 and not crossing:continue
            elif not aggressive or gap>max(1,sight):continue
        frozen=max(0,(thaw-f['t'])/1000) if m[12] and thaw else 0
        if frozen>horizon:continue
        steps=attack_distance(name,cell,target,attack_range,math.ceil((horizon-frozen)/speed))
        arrival=frozen+steps*speed
        if arrival<=horizon:
            attack=f['elig'].get(mid,[0,0,0,0,400])[4]
            arrivals.append((arrival,mid,max(1,attack),cell,m[5]))
    # Knight can hold one already-engaged melee pursuer on the approach;
    # standing on a nearby cell alone does not block a monster in rAthena.
    guard=pos(knight)
    if f['pull']!=K and knight[6]>knight[7]*.6 and not knight[16] and not knight[12]:
        held=next((entry for entry in arrivals if entry[4]==K and dist(guard,entry[3])<=2 and dist(guard,target)>=2 and dist(entry[3],target)>=dist(guard,target)),None)
        if held:arrivals.remove(held)
    return arrivals

@lru_cache(None)
def attack_delays():
    # B_M records attack animation time. Swing interval is the DB AttackDelay.
    delays={}
    root=Path('companion-dev/runtime/m94/db')
    for path in (root/'re/mob_db.yml',root/'import/mob_db.yml'):
        species=None
        for line in path.read_text().splitlines():
            match=re.match(r'  - Id: (\d+)',line)
            if match:species=int(match[1])
            elif species and (match:=re.match(r'    AttackDelay: (\d+)',line)):
                delays[species]=int(match[1])
    return delays

def camp_margin(f, end, help_if_hit, floors, model):
    """Seconds of reserve after a fresh melee add starts hitting a camp member."""
    actors=f['a']; healer=actors[f.get('healer',P)];guard=actors[K]
    name={448:'yuno_fild07',450:'yuno_fild09'}[healer[3]]
    threats=[(max(1,f['elig'][mid][4]),max(.2,attack_delays().get(m[2],m[13])/1000))
             for mid,m in f['m'].items() if mid in f['elig'] and m[6]>0
             and f['motion'].get(mid,(True,))[0] and not 1078<=m[2]<=1085]
    attack=max((d for d,_ in threats),default=400)
    sustained=max((d/period for d,period in threats),default=400.)
    margins={}
    for i in ((OWNER,W,H,CAMP) if CAMP in actors else (OWNER,W,H)):
        a=actors[i]; victim=tuple(a[10:12]) if a[12] else pos(a)
        response=help_if_hit[i] if help_if_hit[i] is not None else math.inf
        if f['pull']==f.get('healer',P):
            steps=attack_distance(name,end,victim,8,110)
            response=max(response,steps*healer[20]/1000*1.6+
                         model['priest-near' if steps==0 else 'priest-far']+.4)
        # A ready defender can peel one fresh add, never an entire visible wave.
        if guard[6]>.6*guard[7] and not guard[16] and not any(
                m[5]==i or m[5]==K for m in f['m'].values()):
            guard_start=end if f['pull']==K else pos(guard)
            steps=attack_distance(name,guard_start,victim,1,16)
            peel=max(0,guard[17]-f['t'],guard[18]-f['t'])/1000+steps*guard[20]/1000*1.6+1.2
            # Target switches observed in stress trials can take several
            # seconds or fail. Preserve a finite healer fallback.
            if response<15:
                response=min(response,peel+4.8)
        shield=f['buff'].get((i,39),(0,0,0))
        absorb=min(shield[0],shield[1]*attack) if shield[2]>=f['t']+1000*response else 0
        reserve=a[6]+absorb-floors[i]-attack
        margins[i]=reserve/sustained-response
    return margins

def wizard_cover(f, pull_goal=None):
    """Observable first-hit protection, evaluated again after any preparation."""
    wiz=f['a'][W]
    hp,hits,expiry=f['buff'].get((W,39),(0,0,0))
    first=max((v[4] for v in f['elig'].values()),default=400)
    if hp>=first and hits>0 and expiry>=f['t']+2000:
        return True
    guard=f['a'][K]
    if f['pull']==K:
        # A short departure leaves a second responder within interception range.
        # Recheck both ends of the step; a distant Knight cannot cover camp.
        healer=f['a'][f.get('healer',P)]
        if not pull_goal or not all(f['cover'][W]) or healer[12] or healer[16]:
            return False
        return (max(dist(pos(guard),pos(wiz)),dist(pull_goal,pos(wiz)))<=8
                and dist(pos(healer),pos(wiz))<=6 and not any(m[5]==W for m in f['m'].values()))
    return (f['pull']==P and guard[6]>.6*guard[7] and not guard[12] and
            not guard[16] and dist(pos(guard),pos(wiz))<=2 and
            all(f['cover'][W]) and any(f['t']-t<=5000 and mid in f['m'] and f['m'][mid][5]==K
            for mid,t in f.get('peels',{}).items()) and not any(m[5]==W for m in f['m'].values()))

def prepare_camp(f,grid,end,help_if_hit,floors,model,waiting):
    """Price one preparatory action against holding at this same waypoint."""
    if waiting or not end:
        return None
    actors=f['a']; now=f['t']; priest=f.get('healer',P); healer=actors[priest]
    rank,enabled,sp=f['sk'].get((priest,73),(0,0,0))
    heal_cost=f['sk'].get((priest,28),(0,0,40))[2]
    initial=camp_margin(f,end,help_if_hit,floors,model)
    def value(frame, margins):
        return min(margins.values())-sum(max(0,-v) for v in margins.values())- (0 if wizard_cover(frame,end) else 4)
    base=value(f,initial)
    if not math.isfinite(base):return None
    choices=[]
    for member in (W,OWNER,H):
        for actor,skill,reach in ((priest,73,9),(K,0,1)):
            if actor==K and f['pull']==K:continue
            a=actors[actor];target=actors[member]
            if a[16] or a[6]<a[7]*.6 or target[12]:continue
            if skill and (not enabled or not rank or healer[8]-sp<3*heal_cost):continue
            start=pos(a); goal=pos(target)
            # Find a walkable staging cell with line of sight to the target.
            name={448:'yuno_fild07',450:'yuno_fild09'}[a[3]]
            if attack_distance(name,start,goal,reach,0)==0:path=[]
            else:
                path=grid.route(start,goal)
                if not path:continue
                j=next((n for n,q in enumerate(path) if attack_distance(name,q,goal,reach,0)==0),None)
                if j is None:continue
                path=path[:j+1]
            if not path and not skill:continue
            cell=path[-1] if path else start
            travel=sum(1.4 if x[0]!=y[0] and x[1]!=y[1] else 1 for x,y in zip([start]+path,path))*a[20]/1000*1.6
            delay=max(travel,max(0,a[17]-now,a[18]-now,f['cd'].get((actor,skill),0)-now)/1000)
            # DB upper cast bound, then preserve the native two-second act delay.
            seconds=delay+(4 if skill else .5)
            if seconds>10 or any(m[5]==actor for m in f['m'].values()):continue
            proj=dict(f,t=now+round(seconds*1000),a=dict(actors),buff=dict(f['buff']))
            proj['a'][actor]=a[:];proj['a'][actor][4:6]=cell
            proj['a'][actor][10:13]=[*cell,0]
            if skill:
                # SP and remaining physical shield after the post-cast interval.
                proj['a'][actor][8]-=sp
                hits=reachable_wave(f,member,seconds)
                points=target[7]*(10+2*rank)//100
                count=5+rank//2
                for arrival,mid,damage,_,_ in hits:
                    swings=1+int((seconds-arrival)/max(.2,attack_delays().get(f['m'][mid][2],1000)/1000))
                    points-=swings*damage;count-=swings
                if points<=0 or count<=0:continue
                proj['buff'][member,39]=(points,count,proj['t']+118000)
            prep_damage={}
            for member_id in (W,H,OWNER):
                for arrival,mid,damage,_,_ in reachable_wave(f,member_id,seconds):
                    interval=max(.2,attack_delays().get(f['m'][mid][2],1000)/1000)
                    prep_damage[member_id]=prep_damage.get(member_id,0)+damage*(1+int((seconds-arrival)/interval))
            for member_id,damage in prep_damage.items():
                ally=proj['a'][member_id][:]
                ally[6]-=damage
                proj['a'][member_id]=ally
            if any(proj['a'][i][6]<=floors[i] for i in prep_damage):continue
            margins=camp_margin(proj,end,help_if_hit,floors,model)
            improvement=value(proj,margins)-base
            score=improvement-seconds*.3-sum(prep_damage.values())/1100-(sp/max(1,heal_cost) if skill else 0)
            if score>0:
                choices.append(dict(actor=actor,action='kyrie' if skill else 'guard_position',target=member,
                    cell=cell,seconds=round(seconds,3),sp=sp if skill else 0,score=round(score,3),
                    potential_ready=min(margins.values())>0 and wizard_cover(proj,end),
                    remaining_shield=proj['buff'].get((member,39),(0,0,0))[:2]))
    return max(choices,key=lambda v:v['score'],default=None)

class Planner:
    def __init__(self,model,trial_radius=None):
        self.trial_radius=trial_radius
        self.model=model;self.first_tick=None;self.strategy_due=0;self.team_due=0;self.strat={}
        self.outside=False;self.return_seen=False
    def think(self,f,world):
        t=f['t'];actors=f['a']; pull=f['pull']; priest=f.get('healer',P)
        aggro=Counter(m[5] for m in f['m'].values())
        history=[v for v in world.hits if t-8000<v[0]<=t and v[1] in f['m']]
        floors={};ttd={};eta={}
        for i,a in actors.items():
            hits=[v for v in history if v[2]==i]
            floors[i]=max([a[7]*.15]+[v[4] for v in hits])
            dps=max(sum(v[4] for v in hits)/8,sum(v[4] for v in hits if v[0]>t-2000)/2,aggro[i]*a[7]*.025)
            ttd[i]=min(120,(a[6]-floors[i])/max(1,dps))
            base,bucket=partition(f,i)
            eta[i]=round(base+self.model[bucket],2) if all(f['cover'][i][1:3]) else None
        waiting={i for i,a in actors.items() if needs_heal(a)}
        help_if_hit=eta.copy()
        eta={i:(delay if i in waiting else None) for i,delay in eta.items()}
        camp_gap=dist(pos(actors[pull]),f['anchor'])
        if camp_gap>9:self.outside=True
        if self.outside and camp_gap<=5:self.return_seen=True
        emergencies=[i for i in actors if i in waiting and actors[i][6]<actors[i][7]*.5]
        # Native-frame reflex suggestions; no command emitter exists.
        reflex=('heal',min(emergencies,key=ttd.get)) if emergencies else ('kyrie',pull) if aggro[pull]>4 and (pull,39) not in f['buff'] else ('heal',min(waiting,key=lambda i:actors[i][6]/actors[i][7])) if actors[priest][6]>.5*actors[priest][7] and waiting else ('hold',0)
        if reflex[0] in ('heal','kyrie'):
            skill=28 if reflex[0]=='heal' else 73
            rank,enabled,cost=f['sk'].get((priest,skill),[1,1,40])
            if not rank or not enabled or actors[priest][8]<cost or f['cd'].get((priest,skill),0)>t or not all(f['cover'][reflex[1]][:2]):
                reflex=('regroup',reflex[1])
        if t<self.team_due:return dict(t=t,reflex=reflex)
        self.team_due=max(t,self.team_due)+500 if not self.team_due else max(t-499,self.team_due)+500
        reasons=[]
        for i in actors:
            if actors[i][6]<=floors[i] or ttd[i]<max(8,(help_if_hit[i] or 120)+2):reasons.append('help_late')
        if actors[pull][6]<actors[pull][7]*.6:reasons.append('puller_hp')
        if not all(f['cover'][W][1:3]):reasons.append('healer_unavailable')
        heal=f['sk'].get((priest,28),[10,1,40]);sg=f['sk'].get((W,89),[10,1,78])
        if actors[priest][8]<3*heal[2] or actors[W][8]<2*sg[2] or not sg[0]*sg[1]:reasons.append('reserve')
        if t>=self.strategy_due or self.strat.get('protected')!=wizard_cover(f):
            grid=Influence(f,world)
            start=pos(actors[pull]);camp=f['anchor']
            targets=[m for m in grid.local if all(f['elig'].get(m[1],[1,1])[:2]) and not m[5] and (0 if self.trial_radius else 1)<dist(start,m[3:5])<=96 and not grid.blocked(tuple(m[3:5]))]
            if self.trial_radius:
                # Filter only outbound candidates. All monsters still contribute to risk.
                targets=[m for m in targets if dist(camp,m[3:5])<=self.trial_radius and
                         attack_distance({448:'yuno_fild07',450:'yuno_fild09'}[actors[pull][3]],
                                         pos(actors[priest]),tuple(m[3:5]),6,0)==0]
            if 'admission_offer' in f:
                targets=[m for m in targets if m[1]==f['admission_offer']]
            ranked=sorted(targets,key=lambda m:sum(dist(m[3:5],b[3:5])<=6 for b in targets)/(4+dist(start,m[3:5])),reverse=True)
            nearest=sorted(targets,key=lambda m:dist(start,m[3:5]))
            route=[];prep_end=None
            for candidate in ranked[:1]+nearest[:6]:
                end=tuple(candidate[3:5])
                path=grid.route(start,end)
                # Only authorize a reachable portion of this route. A waypoint
                # short of the mob is movement permission, never permission to tag.
                for index in dict.fromkeys((len(path), min(len(path),6), min(len(path),3),min(len(path),1))):
                    if not index:continue
                    if 'admission_offer' in f and (index!=len(path) or path[-1]!=end):continue
                    waypoint=path[index-1]
                    if not self.return_seen and dist(waypoint,camp)>12:continue
                    if prep_end is None or dist(start,waypoint)<dist(start,prep_end):prep_end=waypoint
                    if min(camp_margin(f,waypoint,help_if_hit,floors,self.model).values())>0:
                        route=path[:index]
                        break
                if route:break
            sites=[(camp[0]+dx,camp[1]+dy) for dx,dy in ((9,0),(-9,0),(0,9),(0,-9),(8,8),(-8,-8),(-8,8),(8,-8))]
            candidates=[p for p in sites if not grid.blocked(p)]
            self.strat=dict(protected=wizard_cover(f),prep_end=prep_end,tag=bool(route and route[-1]==end),mode='recover' if reasons else 'gather',route=route,site=min(candidates,key=lambda p:max(grid.risk(p,sec) for sec in (1,4,8))+.12*dist(p,pos(actors[priest])),default=None),capacity=max(0,f['cap']-len(f['pack'])),camp_risk=round(grid.risk(camp),2))
            self.strategy_due=t+2500
        current=pos(actors[pull]); dest=tuple(actors[pull][10:12])
        # Protect the entire production segment as well as our proposed route.
        route=self.strat['route']
        steps=max(1,dist(current,dest))
        line=[(round(current[0]+(dest[0]-current[0])*j/steps),round(current[1]+(dest[1]-current[1])*j/steps)) for j in range(steps+1)]
        conflict=any(any(dist(p,q)<=4 for p in route+line) for q in f['peer'])
        if conflict:reasons.append('player_on_path')
        # Empty damage history cannot certify capacity. Price the first volley
        # of the remaining pack, even before those mobs have acquired a target.
        if self.first_tick is None:self.first_tick=t
        if t-self.first_tick<8000:reasons.append('initial_dps_window')
        endpoint=route[-1] if route else current
        margins=camp_margin(f,endpoint,help_if_hit,floors,self.model)
        if min(margins.values())<=0:reasons.append('camp_response_late')
        reachable={};extra=f['cap']-len(f['pack'])
        for actor in ((OWNER,W,H,CAMP) if CAMP in actors else (OWNER,W,H)):
            horizon=min(8,max(2,help_if_hit[actor] or 8))
            hits=reachable_wave(f,actor,horizon)
            reachable[actor]=[m for _,m,_,_,_ in hits]
            shield=f['buff'].get((actor,39),(0,0,0))
            damage=sum(h[2]*1.15 for h in hits)
            shield_hp=min(shield[0],sum(sorted((h[2] for h in hits),reverse=True)[:max(0,shield[1])])) if shield[2]>=t+1000*horizon else 0
            budget=actors[actor][6]-floors[actor]+shield_hp-damage
            if budget<=0:reasons.append('reachable_volley')
            # Reserve only for reachable unclaimed adds; counted train members
            # already occupy their slots. One additional proposed tag at a time.
            extra=min(extra,f['cap']-len(f['pack']|set(reachable[actor])))
        self.strat['capacity']=max(0,extra)
        if pull==P and any(i!=P and (priest==P or not all(f['cover'][i])) for i in waiting):
            reasons.append('finish_pending_heal')
        # Use the camp defenders who will remain after the departure. A
        # moving backline and a helper in cast/act lock cannot be pledged
        # to intercept at the backline's current coordinates.
        for i in (OWNER,W,H):
            a=actors[i]
            endpoint=tuple(a[10:12]) if a[12] else pos(a)
            if pull==P:
                guard=actors[K]
                if (reachable[i] or i in waiting) and (guard[16] or guard[6]<guard[7]*.6 or max(dist(pos(guard),pos(a)),dist(pos(guard),endpoint))>8):
                    reasons.append('camp_guard_unavailable');break
            else:
                cover=f['cover'][i]
                if not all(cover[:3]) or (not all(cover[3:]) and (i in waiting or a[12])):
                    reasons.append('camp_healer_unavailable');break
        if not wizard_cover(f,route[-1] if route else None):reasons.append('wizard_first_hit_uncovered')
        if not route:reasons.append('no_route')
        if not self.strat['capacity']:reasons.append('camp_capacity')
        scripts=[('production','pull_short','guard','peel'),('production','camp_heal','self_pull','shield'),('production','sg1_max','sgmax','wait'),('production','cleanup','hold')]
        camp=f['anchor']
        engaged=[m for m in f['m'].values() if m[5] in actors or m[1] in f['pack']]
        victims=[m for m in engaged if dist(m[3:5],camp)<=5]
        active=len(victims)
        bystanders=[m for m in f['m'].values() if m not in victims and dist(m[3:5],camp)<=5]
        splash_ok=len(set(f['pack'])|{m[1] for m in victims+bystanders})<=f['cap']+2 and all(all(f['elig'].get(m[1],[1,1])[:2]) for m in bystanders)
        risk_target=min(ttd,key=ttd.get)
        wizard_threat=any(m[5]==W for m in engaged)
        ammo=sum(n for (actor,item),n in f['supply'].items() if actor==H and 1750<=item<=1775)
        if wizard_threat and (not f['cover'][W][0] or actors[W][16]):reasons.append('wizard_exposed')
        if any(m[5] in actors and dist(m[3:5],camp)<=4 for m in engaged) and not f['cover'][W][0]:reasons.append('camp_without_healer')
        if aggro[pull]>4 and (pull,39) not in f['buff']:reasons.append('puller_without_shield')
        if world.interrupt_until>t and active:reasons.append('wave_interrupted')
        base=('production',)*4
        def score(team):
            knight,priest_script,wizard,hunter=team
            if (priest_script=='self_pull' and pull!=P) or (knight=='pull_short' and pull!=K):return -1e9
            advances=(priest_script=='self_pull' or knight=='pull_short' or (team[0 if pull==K else 1]=='production' and not f['inbound']))
            if advances and reasons:return -1e9
            if wizard.startswith('sg') and (not sg[0]*sg[1] or actors[W][8]<sg[2] or not self.strat['site']):return -1e9
            if wizard.startswith('sg') and (not splash_ok or f['cd'].get((W,89),0)>t or actors[W][16] or t<actors[W][17]):return -1e9
            if priest_script=='self_pull' and any(aggro[i] and ttd[i]<base_eta(f,i)[0]+10 for i in (OWNER,W,H)):return -1e9
            hp={m[1]:float(m[6]) for m in victims}
            wave=any(v[2]==W and v[3]==89 and v[0]+v[7]>t for v in world.fields.values())
            remaining_hp={i:float(a[6]) for i,a in actors.items()}
            heal_budget=actors[priest][8]//max(1,heal[2])
            risk=reward=0.
            for sec in range(1,9):
                for i in actors:
                    incoming=max(0,actors[i][6]-floors[i])/max(.5,ttd[i]) if ttd[i]<120 else 0
                    if i==W and knight in ('peel','guard'):incoming*=.7
                    remaining_hp[i]-=incoming
                hurt=min(actors,key=lambda i:remaining_hp[i]/actors[i][7])
                if (CAMP in actors or priest_script in ('camp_heal','production')) and heal_budget and f['cover'][hurt][0] and sec>=base_eta(f,hurt)[0] and sec%2==0 and remaining_hp[hurt]<.77*actors[hurt][7]:
                    remaining_hp[hurt]=min(actors[hurt][7],remaining_hp[hurt]+1100);heal_budget-=1
                risk+=sum(max(0,(floors[i]-remaining_hp[i])/max(1,floors[i])) for i in actors)
                live=[m for m in victims if hp[m[1]]>0]
                if not live:continue
                cleanup=min(live,key=lambda m:hp[m[1]])
                for m in live:
                    dmg=0
                    if m is cleanup and ammo>0 and hunter!='hold' and m[1] not in (f['pack'] if not f['release'] and not f['inbound'] else set()):
                        dmg+=160 if hunter=='cleanup' else 120
                    if m is cleanup and knight not in ('pull_short','peel') and not advances:dmg+=100
                    if wave and sec<=3 or not wave and splash_ok and wizard!='wait' and sec>=(2 if wizard=='sg1_max' else 4):
                        dmg+=(250 if wizard=='sg1_max' and sec<5 else 580)*{1:.4,2:1.,3:1.5,4:.6}.get(m[9],1.)
                    hp[m[1]]-=dmg
                    if hp[m[1]]<=0:reward+=f['elig'].get(m[1],[0,0,2000])[2]
            future=(min(self.strat['capacity'],3)*180 if advances else 0)
            return round((reward+future)/8-900*risk-.3*sum(v!='production' for v in team),3)
        best=base;value=score(best)
        for _ in range(3):
            improved=False
            for idx,options in enumerate(scripts):
                for option in options:
                    test=best[:idx]+(option,)+best[idx+1:]
                    candidate=score(test)
                    if candidate>value:best,value=test,candidate;improved=True
            if not improved:break
        if value<=-1e8:best=('guard','camp_heal','wait','hold')
        shield={}
        for (actor,buff),(points,hits,expiry) in f['buff'].items():
            if buff!=39:continue
            attackers=[m for m in engaged if m[5]==actor and dist(m[3:5],pos(actors[actor]))<=m[11]+1]
            hits_per_sec=sum(1000/max(200,m[13]) for m in attackers)
            incoming=sum(v[4] for v in history if v[2]==actor)/8
            shield[actor]=min(expiry,t+round(1000*min(hits/max(.01,hits_per_sec),points/max(1,incoming))))
        intents={'Knight':{'script':best[0],'focus':W if wizard_threat else pull},
                 'Priest':{'script':best[1],'focus':reflex[1] or pull},
                 'Wizard':{'script':best[2],'cell':camp,'stand':self.strat['site']},
                 'Hunter':{'script':best[3],'focus':next((m[1] for m in sorted(victims,key=lambda m:m[6]) if m[1] not in f['pack']),0)}}
        if route and not reasons:
            mover=intents[ALIASES[0 if pull==K else 1]]
            mover.update(pull_goal=route[-1],can_tag=self.strat['tag'])
        elif pull==P and 'camp_guard_unavailable' in reasons:
            intents['Knight']=dict(script='guard',focus=i,cell=endpoint)
        prep=None
        if reasons and not set(reasons).difference({'wizard_first_hit_uncovered','camp_response_late','no_route','camp_guard_unavailable','camp_healer_unavailable'}):
            # Current peers and fields can invalidate a staging path between scans.
            prep=prepare_camp(f,Influence(f,world),route[-1] if route else self.strat['prep_end'],help_if_hit,floors,self.model,waiting)
        if CAMP in actors:
            intents['CampPriest']=dict(script=reflex[0] if reflex[0]!='hold' else 'camp_support',focus=reflex[1] or W)
        if prep:
            role='CampPriest' if prep['actor']==CAMP else 'Priest' if prep['actor']==P else 'Knight'
            intents[role]=dict(script=prep['action'],cell=prep['cell'],focus=prep['target'])
            best=tuple(intents[name]['script'] for name in ALIASES)
        if CAMP in actors:best=(*best,intents['CampPriest']['script'])
        return dict(t=t,prep=prep,camp_margin={i:round(v,2) if math.isfinite(v) else None for i,v in margins.items()},reflex=reflex,team=best,intents=intents,shield_until=shield,baseline_score=score(base),score=value,reason=sorted(set(reasons)),safe=not reasons,ttd=ttd,floor=floors,eta=eta,help_if_hit=help_if_hit,reachable=reachable,capacity=self.strat['capacity'],strategy=self.strat['mode'],weakest=risk_target,splash_ok=splash_ok,site=self.strat['site'],goal=route[-1] if route else None,peer_conflict=conflict)

def main():
    mode,path,model=sys.argv[1:]
    world=World();planner=Planner(json.loads(Path(model).read_text()))
    for k,f in world.frames(readlog(Path(path),mode=='live')):
        if k=='frame':
            print(json.dumps(planner.think(f,world),separators=(',',':')),flush=True)
if __name__=='__main__':main()
