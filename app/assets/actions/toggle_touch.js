registerAction({
  apiVersion:1,id:'builtin.toggleTouch',name:'切换触控面板',inputs:['button'],ticks:false,fields:[],
  onEvent(ctx) {
    return ctx.event.type==='press' ? [{type:'toggleTouchPanel',channel:ctx.touch.open?ctx.touch.channel:ctx.selected}] : [];
  }
});
