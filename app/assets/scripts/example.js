registerAction({
  apiVersion: 1,
  id: 'user.stepStrength',
  name: '点按调强',
  inputs: ['button'],
  fields: [
    { key: 'target', label: '目标通道', type: 'select', default: 'selected', options: [
      { value: 'selected', label: '当前选中' },
      { value: 'A', label: 'A 通道' },
      { value: 'B', label: 'B 通道' }
    ] },
    { key: 'step', label: '每次增减', type: 'number', min: -50, max: 50, default: 5 }
  ],
  onEvent(ctx, state) {
    if (ctx.event.type !== 'press') return [];
    return [{ type: 'adjustBase', channel: ctx.target, value: ctx.config.step }];
  }
});
