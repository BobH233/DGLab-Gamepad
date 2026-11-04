registerAction({
  apiVersion:1,id:'builtin.stickCursor',name:'摇杆移动光标',inputs:['stick'],ticks:true,
  fields:[
    {key:'target',label:'波形目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'modifier',label:'触控死区旁路键',type:'select',default:'rightStick',options:[{value:'none',label:'不启用'},{value:'leftStick',label:'L3'},{value:'rightStick',label:'R3'}]}
  ],
  onEvent(ctx,state) {
    if(ctx.touch.open) {
      if(!ctx.touch.surface || ctx.event.type!=='tick') return [];
      const bypass=ctx.config.modifier!=='none'&&ctx.rawInput[ctx.config.modifier]>0.5;
      const x=bypass?ctx.input.rawX:ctx.input.x,y=bypass?ctx.input.rawY:ctx.input.y,radius=Math.hypot(x,y);
      if(bypass&&radius===0) {
        if(state.active&&state.x===0.5&&state.y===0.5) return [];
        state.x=0.5;state.y=0.5;state.active=true;
        return [{type:'touchPoint',x:0.5,y:0.5,active:true}];
      }
      if(!bypass&&radius<0.02) {
        if(!state.active) return [];
        state.active=false;
        return [{type:'touchPoint',x:state.x,y:state.y,active:false}];
      }
      const scale=radius/Math.max(Math.abs(x),Math.abs(y));
      state.x=Math.min(1,Math.max(0,0.5+0.5*x*scale));
      state.y=Math.min(1,Math.max(0,0.5+0.5*y*scale));
      state.active=true;
      return [{type:'touchPoint',x:state.x,y:state.y,active:true}];
    }
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
