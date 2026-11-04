registerAction({
  apiVersion:1,id:'builtin.waveform',name:'切换波形',inputs:['button'],ticks:false,
  fields:[
    {key:'target',label:'目标通道',type:'select',default:'selected',options:[{value:'selected',label:'当前选中'},{value:'A',label:'A 通道'},{value:'B',label:'B 通道'}]},
    {key:'mode',label:'选择方式',type:'select',default:'fixed',options:[{value:'fixed',label:'指定波形'},{value:'sequence',label:'顺序轮换'},{value:'random',label:'随机选择'}]},
    {key:'waveform',label:'指定波形',type:'waveform',default:'d6f83af0'},
    {key:'list',label:'轮换列表',type:'waveforms',default:['d6f83af0','eea0e4ce','7eae1e5f']}
  ],
  onEvent(ctx,state) {
    if(ctx.event.type!=='press') return [];
    const list=ctx.config.list;
    let id=ctx.config.waveform;
    if(ctx.config.mode==='sequence') id=list[(list.indexOf(ctx.channels[ctx.target].waveform)+1)%list.length];
    if(ctx.config.mode==='random') id=list[Math.min(list.length-1,Math.floor(ctx.random*list.length))];
    return [{type:'waveform',channel:ctx.target,id}];
  }
});
