registerAction({
  apiVersion:1, id:'builtin.linear', name:'线性强度', inputs:['trigger'],
  fields:[
    {key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'unit',label:'增减方式',type:'select',default:'absolute',options:[{value:'absolute',label:'固定数值'},{value:'percent',label:'基础强度百分比'}]},
    {key:'amount',label:'满行程增减量',type:'number',min:-200,max:200,default:30}
  ],
  onEvent(ctx,state) {
    if (ctx.event.type !== 'value') return [];
    const v=ctx.event.value;
    if (v <= 0.01) { state.target=null; return [{type:'clearOverlay'}]; }
    if (!state.target) state.target=ctx.target;
    return [{type:'offset',channel:state.target,unit:ctx.config.unit,value:ctx.config.amount*v}];
  }
});
