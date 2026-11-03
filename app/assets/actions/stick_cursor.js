registerAction({
  apiVersion:1,id:'builtin.stickCursor',name:'摇杆移动波形光标',inputs:['stick'],
  fields:[{key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]}],
  onEvent(ctx,state) {
    if(ctx.event.type!=='tick') return [];
    const x=ctx.input.x,y=ctx.input.y, magnitude=Math.max(Math.abs(x),Math.abs(y));
    if(magnitude<0.35) { state.direction=null; state.target=null; state.wait=0; return []; }
    const direction=Math.abs(x)>Math.abs(y)?(x>0?'right':'left'):(y>0?'down':'up');
    if(state.direction!==direction) { state.direction=direction; state.target=ctx.target; state.wait=0.4; return [{type:'moveCursor',channel:state.target,direction}]; }
    state.wait-=ctx.event.dt;
    if(state.wait<=0) { state.wait=0.14; return [{type:'moveCursor',channel:state.target,direction}]; }
    return [];
  }
});
