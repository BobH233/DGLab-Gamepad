registerAction({
  apiVersion:1,id:'builtin.select',name:'选择通道',inputs:['button'],ticks:false,
  fields:[{key:'channel',label:'选择方式',type:'select',default:'toggle',options:[{value:'toggle',label:'A / B 切换'},{value:'A',label:'选中 A'},{value:'B',label:'选中 B'}]}],
  onEvent(ctx,state) {
    return ctx.event.type==='press' ? [{type:'selectChannel',channel:ctx.config.channel==='toggle'?(ctx.selected==='A'?'B':'A'):ctx.config.channel}] : [];
  }
});
