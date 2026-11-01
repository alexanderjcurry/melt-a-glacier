"""Greedy-player pacing simulation. Mirrors scripts/balance.gd; keep them in sync.
Run: python3 tools/pacing_sim.py  -> hours to finish and minute each layer cleared."""
TOOLS=[("Hair Dryer",1,0),("Heat Lamp",8,200),("Blowtorch",60,8000),("Flamethrower",500,4e5),("Lava Hose",5000,2.5e7),("Orbital Mirror",60000,2e9)]
TOOL_LAYER=[0,1,3,5,7,9]
HELP=[("Penguin",0.4,25),("Sauna",4,800),("Volcano",45,4e4),("Hot Spring",600,2.5e6),("Sun Sat",9000,2e8)]
HGROW=1.17
STAT={"heat":(15,1.45),"size":(80,1.55),"auto":(500,1.6),"sell":(300,1.7)}
def run(layers,active=0.5,verbose=False):
    N=len(layers)
    t=0;water=0;li=0;hp=layers[0];tool=0;lv={x:0 for x in STAT};hc=[0]*5;times=[]
    while li<N and t<30*3600:
        heat=TOOLS[tool][1]*(1+0.25*lv["heat"])*(1+0.15*lv["size"])
        auto=sum(hc[i]*HELP[i][1] for i in range(5))*(1+0.25*lv["auto"])
        rate=heat*5*active+auto
        m=rate
        while m>0 and li<N:
            d=min(m,hp);hp-=d;m-=d;water+=d*(1+0.1*lv["sell"])
            if hp<=0:
                times.append(round(t/60));li+=1
                if li<N:hp=layers[li]
        t+=1
        while True:
            opts=[]
            if tool+1<len(TOOLS) and li>=TOOL_LAYER[tool+1]:
                c=TOOLS[tool+1][2];g=(TOOLS[tool+1][1]/TOOLS[tool][1]-1)*heat*5*active;opts.append((g/c,c,"tool",0))
            for i,h in enumerate(HELP):
                c=h[2]*HGROW**hc[i];g=h[1]*(1+0.25*lv["auto"]);opts.append((g/c,c,"help",i))
            for kk,(b,gr) in STAT.items():
                c=b*gr**lv[kk]
                if kk=="heat":g=heat*5*active*0.25/(1+0.25*lv[kk])
                elif kk=="size":g=heat*5*active*0.15/(1+0.15*lv[kk])
                elif kk=="auto":g=auto*0.25/(1+0.25*lv[kk])
                else:g=rate*0.1/(1+0.1*lv[kk])
                opts.append((g/c,c,"stat",kk))
            opts.sort(key=lambda o:-o[0]);best=opts[0]
            if best[1]>water:break
            water-=best[1]
            if best[2]=="tool":tool+=1
            elif best[2]=="help":hc[best[3]]+=1
            else:lv[best[3]]+=1
    if verbose:print(" tool",tool,"hc",hc,"lv",lv,f"rate {rate:.3g}")
    return t/3600,times

LAYER_HP = [500.0, 3.0e3, 1.8e4, 1.08e5, 6.48e5, 3.89e6, 2.33e7, 1.17e8, 5.25e8, 2.1e9, 6.3e9, 1.57e10]
if __name__ == "__main__":
    for active in (0.5, 0.25):
        h, ts = run(LAYER_HP, active=active)
        print(f"hold {int(active*100)}% of the time: {h:.2f} h, layers cleared at minutes {ts}")
