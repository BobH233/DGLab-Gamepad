registerAction({
  apiVersion:1,id:'builtin.stickStrength',name:'摇杆渐进调强',inputs:['stick'],ticks:true,
  fields:[{key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]}],
  onEvent(ctx,state) {
    if(ctx.event.type!=='tick') return [];
    const y=-ctx.input.y, sign=Math.sign(y);
    if(Math.abs(y)<0.02) { state.time=0; state.target=null; state.sign=0; return []; }
    if(state.sign!==sign) { state.time=0; state.target=ctx.target; state.sign=sign; }
    state.time=Math.min(2,(state.time||0)+ctx.event.dt);
    const rate=Math.min(30,3+27*state.time/2)*Math.pow(Math.abs(y),1.5);
    return [{type:'adjustBase',channel:state.target,value:sign*rate*ctx.event.dt}];
  }
});
