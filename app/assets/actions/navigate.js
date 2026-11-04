registerAction({
  apiVersion:1,id:'builtin.navigate',name:'移动波形光标',inputs:['button'],ticks:true,
  fields:[
    {key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'direction',label:'方向',type:'select',default:'right',options:[{value:'up',label:'上'},{value:'down',label:'下'},{value:'left',label:'左'},{value:'right',label:'右'}]}
  ],
  onEvent(ctx,state) {
    if(ctx.event.type==='press') { state.target=ctx.target; state.elapsed=0; state.next=0.4; return [{type:'moveCursor',channel:state.target,direction:ctx.config.direction}]; }
    if(ctx.event.type==='release') state.target=null;
    if(ctx.event.type==='tick' && state.target) {
      state.elapsed+=ctx.event.dt;
      if(state.elapsed>=state.next) { state.next=state.elapsed+0.14; return [{type:'moveCursor',channel:state.target,direction:ctx.config.direction}]; }
    }
    return [];
  }
});
