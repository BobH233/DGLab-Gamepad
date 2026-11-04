registerAction({
  apiVersion:1,id:'builtin.toggle',name:'启停通道',inputs:['button'],ticks:false,
  fields:[
    {key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'mode',label:'触发方式',type:'select',default:'toggle',options:[{value:'hold',label:'按住反转，松开恢复'},{value:'toggle',label:'点按切换'}]}
  ],
  onEvent(ctx,state) {
    if (ctx.event.type==='press') return [{type:ctx.config.mode==='hold'?'enableOverlay':'toggleEnabled',channel:ctx.target,value:!ctx.channels[ctx.target].enabled}];
    if (ctx.event.type==='release' && ctx.config.mode==='hold') return [{type:'clearOverlay'}];
    return [];
  }
});
