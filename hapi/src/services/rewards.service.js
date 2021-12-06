const { hasuraUtil } = require('../utils')

const save = async payload => {
  const mutation = `
    mutation ($payload: rewards_insert_input!) {
      insert_rewards_one(object: $payload) {
        id
      }
    }  
  `

  const data = await hasuraUtil.instance.request(mutation, {
    payload
  })

  return data.insert_rewards_one
}

module.exports = {
  save
}
