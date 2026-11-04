registerAction({
  apiVersion:1,id:'builtin.confirm',name:'应用选中波形',inputs:['button'],ticks:false,
  fields:[{key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]}],
  onEvent(ctx,state) { return ctx.event.type==='press' ? [{type:'applyCursor',channel:ctx.target}] : []; }
});
