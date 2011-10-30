{WebSocketMock} = require('./websocket.mock.js')
{Stomp} = require('../lib/stomp.js')

class exports.ReflectorServerMock extends WebSocketMock
  # WebSocketMock handlers
  
  handle_send: (msg) =>
    @stomp_dispatch(Stomp.unmarshal(msg))
  
  handle_close: =>
    @_shutdown()
  
  handle_open: =>
    @stomp_init()
    @_accept()
  
  # Stomp server implementation.
  # Keep in mind this Stomp server is 
  # meant to simulate a NullMQ reflector
  
  stomp_init: ->
    @transactions = {}
    @subscriptions = {}
    @messages = []
    @router = setInterval =>
      if @readyState isnt 1 then clearInterval @router
      if @messages.length > 0
        for frame in @messages
          for id, sub of @subscriptions
            if frame? and frame.destination is sub[0]
              sub[1](Math.random(), frame.body)
      @messages = []
    , 100
  
  stomp_send: (command, headers, body=null) ->
    @_respond(Stomp.marshal(command, headers, body))
    
  stomp_send_receipt: (frame) ->
    if frame.error?
      @stomp_send("ERROR", {'receipt-id': frame.receipt, 'message': frame.error})
    else
      @stomp_send("RECEIPT", {'receipt-id': frame.receipt})
    
  stomp_send_message: (destination, subscription, message_id, body) ->
    @stomp_send("MESSAGE", {
      'destination': destination, 
      'message-id': message_id,
      'subscription': subscription}, body)

  stomp_dispatch: (frame) ->
    handler = "stomp_handle_#{frame.command.toLowerCase()}"
    if this[handler]?
      this[handler](frame)
      if frame.receipt
        @stomp_send_receipt(frame)
    else
      console.log "StompServerMock: Unknown command: #{frame.command}"

  stomp_handle_connect: (frame) ->
    @session_id = Math.random()
    @stomp_send("CONNECTED", {'session': @session_id})
    
  stomp_handle_begin: (frame) ->
    @transactions[frame.transaction] = []
    
  stomp_handle_commit: (frame) ->
    transaction = @transactions[frame.transaction]
    for frame in transaction
      @messages.push(frame)
    delete @transactions[frame.transaction]

  stomp_handle_abort: (frame) ->
    delete @transactions[frame.transaction]

  stomp_handle_send: (frame) ->
    if frame.transaction
      @transactions[frame.transaction].push(frame)
    else
      @messages.push(frame)

  stomp_handle_subscribe: (frame) ->
    sub_id = frame.id or Math.random()
    cb = (id, body) => @stomp_send_message(frame.destination, sub_id, id, body)
    @subscriptions[sub_id] = [frame.destination, cb]

  stomp_handle_unsubscribe: (frame) ->
    if frame.id in Object.keys(@subscriptions)
      delete @subscriptions[frame.id]
    else
      frame.error = "Subscription does not exist"
        
  stomp_handle_disconnect: (frame) ->
    @_shutdown()
  
  # Test helpers
  
  test_send: (sub_id, message) ->
    msgid = 'msg-' + Math.random()
    @subscriptions[sub_id][1](msgid, message)
  