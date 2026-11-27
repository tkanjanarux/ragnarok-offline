#!/usr/bin/env python3
"""Compile the production outcome policy and verify all 100 rolls for both choices.
This does not claim packet/inventory testing of every random failure outcome.
"""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'server/cash-shop/native/catalogue_exchange.inc').read_text()
start=s.index('static constexpr int catalogue_card_outcome(');end=s.index('\n}\n',start)+3
code=s[start:end]+'''
#include <cassert>
int main() {
    for (int choice=1;choice<=2;++choice) {
        int count[6]={};
        for (int roll=0;roll<100;++roll) ++count[catalogue_card_outcome(roll,choice)];
        assert(count[1]==90 && count[2]==2 && count[5]==2);
        assert(count[choice==1?3:4]==6 && count[choice==1?4:3]==0);
        assert(catalogue_card_outcome(1,choice)==2);
        assert(catalogue_card_outcome(8,choice)==5);
        assert(catalogue_card_outcome(9,choice)==5);
        assert(catalogue_card_outcome(10,choice)==1);
    }
}
'''
with tempfile.TemporaryDirectory(prefix='cash-card-policy-') as d:
 p=Path(d);(p/'test.cpp').write_text(code)
 subprocess.run(['c++','-std=c++17','-Wall','-Wextra','-Werror',str(p/'test.cpp'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
print('PASS: production card policy, 200 roll/protection combinations and boundaries')
