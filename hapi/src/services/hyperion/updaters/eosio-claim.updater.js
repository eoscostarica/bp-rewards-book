const exchangeService = require('../../exchange.service')
const rewardsService = require('../../rewards.service')

module.exports = {
  type: 'eosio:claimrewards',
  includeInlineActions: true,
  apply: async (action, inlineActions) => {
    try {
      const config = { tokenName: 'proton' }
      const producer = action.data.owner
      const producerVotePay = inlineActions.find(
        inlineAction => inlineAction.data.to === producer
      )

      if (!producerVotePay) {
        return
      }

      const rate = await exchangeService.getRate(config.tokenName, 'usd')
      const usd = rate * parseFloat(producerVotePay.data.quantity.split(' ')[0])

      await rewardsService.save({
        rate,
        usd_quantity: usd,
        trxid: action.transaction_id,
        account: producer,
        quantity: producerVotePay.data.quantity,
        claimned_at: action.timestamp
      })
    } catch (error) {
      console.error(`error to sync ${action.action}: ${error.message}`)
    }
  }
}
