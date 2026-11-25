"""Regressions for a real split Heal episode and scenario-specific camp reach."""
from pathlib import Path
from unittest import TestCase,main
from unittest.mock import patch
import planner
from assess import episodes

class CampReach(TestCase):
    def setUp(self):
        self.width=24
        self.cells=bytearray(self.width**2)
        self.patch=patch('planner.terrain',return_value=(self.width,self.width,self.cells))
        self.patch.start();planner.attack_distance.cache_clear()
        def actor(x,y):
            a=[0]*24;a[3:8]=[448,x,y,1000,1000];a[10:12]=[x,y]
            return a
        self.world=dict(t=10000,pull=planner.P,a={planner.W:actor(10,10),planner.K:actor(7,10),planner.P:actor(2,2)},m={},elig={},motion={})
    def tearDown(self):
        self.patch.stop();planner.attack_distance.cache_clear()
    def mob(self,mid,x,y,target,speed=200):
        self.world['m'][mid]=[10000,mid,1369,x,y,target,100,100,speed,0,0,1,0,500]
        self.world['motion'][mid]=[1,9,0]
    def ids(self):
        return {v[1] for v in planner.reachable_wave(self.world,planner.W,1)}
    def test_speed_range_and_thaw(self):
        self.mob(1,6,10,planner.W,200);self.mob(2,6,10,planner.W,500)
        self.assertEqual(self.ids(),{1})
        self.world['m'][1][12]=1;self.world['motion'][1][2]=12000
        self.assertEqual(self.ids(),set())
        self.world['motion'][1][2]=10100
        self.assertEqual(self.ids(),{1})
    def test_obstacle(self):
        self.mob(1,8,10,planner.W)
        for y in range(self.width):self.cells[y*self.width+9]=1
        self.assertEqual(self.ids(),set())
    def test_other_target_and_one_intercept(self):
        self.mob(1,5,10,planner.P);self.mob(2,8,10,planner.K);self.mob(3,8,10,planner.K)
        self.world['a'][planner.K][4:6]=[8,10]
        self.assertEqual(len(self.ids()),1)
        self.world['pull']=planner.K
        self.assertEqual(self.ids(),{2,3})

class DepartureReserve(TestCase):
    def setUp(self):
        CampReach.setUp(self)
        self.addCleanup(CampReach.tearDown,self)
        w=self.world
        for i in (planner.OWNER,planner.H):
            w['a'][i]=w['a'][planner.W][:]
        w['buff']={}
        for a in w['a'].values():
            a[6]=a[7]=3500
            a[20]=150
        self.eta={i:2 for i in w['a']}
        self.floor={i:500 for i in w['a']}
        self.model={'priest-near':2,'priest-far':60}

    def margin(self,end):
        return planner.camp_margin(self.world,end,self.eta,self.floor,self.model)[planner.W]

    def test_guard_adjacent_does_not_replace_distant_heal(self):
        self.world['a'][planner.K][4:6]=[10,10]
        self.assertGreater(self.margin((9,10)),0)
        self.assertLess(self.margin((22,22)),0)

    def test_position_and_forecast_do_not_certify_guard(self):
        w=self.world
        w['a'][planner.K][4:6]=[10,10]
        w['cover']={planner.W:[1]*5}
        self.assertFalse(planner.wizard_cover(w))
        w['peels']={123:w['t']}
        w['m'][123]=[0,123,1369,9,10,planner.K]
        self.assertTrue(planner.wizard_cover(w))
        w['t']+=5100
        self.assertFalse(planner.wizard_cover(w))
        w['buff'][planner.W,39]=(600,2,w['t']+3000)
        self.assertTrue(planner.wizard_cover(w))
        w['buff'][planner.W,39]=(600,0,w['t']+3000)
        self.assertFalse(planner.wizard_cover(w))

    def test_prep_prices_spell_and_never_writes_observed_state(self):
        from copy import deepcopy
        w=self.world
        w.update(cover={planner.W:[1]*5},sk={(planner.P,73):(5,1,25)},cd={})
        w['a'][planner.P][8]=200
        w['a'][planner.K][4:6]=[10,10]
        before=deepcopy(w)
        plan=planner.prepare_camp(w,None,(9,10),self.eta,self.floor,self.model,set())
        self.assertEqual(plan['action'],'kyrie')
        self.assertEqual(plan['sp'],25)
        self.assertGreaterEqual(plan['seconds'],4)
        self.assertEqual(w,before)
        w['a'][planner.P][8]=130
        self.assertIsNone(planner.prepare_camp(w,None,(9,10),self.eta,self.floor,self.model,set()))
        self.assertIsNone(planner.prepare_camp(w,None,(9,10),self.eta,self.floor,self.model,{planner.W}))

    def test_visual_attack_motion_is_not_swing_interval(self):
        self.assertEqual(planner.attack_delays()[1369],1460)

class TwoPriests(TestCase):
    def test_both_healers_native_credits_exclude_potions_and_other_casters(self):
        lines=['B_BOUND start']
        for caster in (planner.P,planner.CAMP,123):
            lines.extend([f'B_SPELL 100 {caster} {planner.W} 28',
                          f'B_HEAL 100 {planner.W} 450 0',
                          f'B_DELIVER 100 {caster} {planner.W} 28 450 0'])
        lines.append(f'B_HEAL 100 {planner.W} 250 0')
        effects=[v for kind,v in planner.World().frames(lines) if kind=='effect']
        self.assertEqual(len(effects),2)
        self.assertTrue(all(v[2]==450 for v in effects))

    def test_five_member_episode_uses_camp_healer_distance(self):
        # A puller out of range must not increase ETA for the stationary healer.
        def actor(i,xy):
            a=[0]*24;a[1]=i;a[4:6]=xy;a[6:8]=[3000,3000];a[20]=150
            return a
        a={i:actor(i,(0,0)) for i in (*planner.TEAM,planner.CAMP)}
        a[planner.P][4:6]=[40,40]
        f=dict(t=1000,a=a,m={},pull=planner.P,healer=planner.CAMP,
               cover={i:(1,1,1,1,1) for i in a})
        self.assertEqual(planner.partition(f,planner.W),(.4,'priest-near'))

class HealNeed(TestCase):
    def test_observed_recovery_ends_the_old_wait(self):
        p=next(Path('reports/companion-brain-stage2/final-09-knight-2').glob('*.log.gz'))
        completed,other=episodes(p)
        ref=1795416666959
        original=next(x for x in other if x['actor']==planner.K and x['t']==ref)
        self.assertEqual((original['end'],original['actual']),('recovered',.002))
        refill=next(x for x in completed if x['actor']==planner.K and x['t']>ref)
        self.assertEqual((refill['t']-ref,refill['actual']),(64382,1.201))
if __name__=='__main__':main()
