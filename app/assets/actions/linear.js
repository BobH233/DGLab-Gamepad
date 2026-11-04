registerAction({
  apiVersion:1, id:'builtin.linear', name:'线性强度', inputs:['trigger'],ticks:false,
  fields:[
    {key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]}
  ],
  onEvent(ctx,state) {
    if (ctx.event.type !== 'value') return [];
    const v=ctx.event.value;
    if (v <= 0.01) { state.target=null; return [{type:'clearOverlay'}]; }
    if (!state.target) state.target=ctx.target;
    const linear=ctx.channels[state.target].linear;
    return [{type:'offset',channel:state.target,unit:linear.unit,value:linear.amount*v}];
  }
});
