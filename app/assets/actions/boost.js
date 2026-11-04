registerAction({
  apiVersion: 1, id: 'builtin.boost', name: '一键开火', inputs: ['button'],ticks:false,
  fields: [
    {key:'target', label:'目标通道', type:'select', default:'selected', options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'mode', label:'触发方式', type:'select', default:'hold', options:[{value:'hold',label:'按住生效'},{value:'toggle',label:'点按切换'}]}
  ],
  onEvent(ctx, state) {
    if (ctx.event.type === 'press') {
      if (ctx.config.mode === 'toggle' && state.active) { state.active=false; return [{type:'clearOverlay'}]; }
      state.active=true; state.target=ctx.target;
      return [{type:'offset',channel:state.target,value:ctx.channels[state.target].boost.amount,unit:'absolute'}];
    }
    if (ctx.event.type === 'release' && ctx.config.mode === 'hold') { state.active=false; return [{type:'clearOverlay'}]; }
    return [];
  }
});
