#!/bin/bash

function sendmsg {
  local dest="$1"
  local addr="$2"
  local msg="$3"

  echo "Sending msg to $2 from $1: $3"
  echo "— [$1]: $3" | kubectl exec -i $1 -- socat -u - UDP4-DATAGRAM:$2
  sleep 2
}

sleep 5

sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 Rebel base, thirty seconds and closing."
sendmsg  darth-vader        225.0.0.11:6666  "⬛ I'm on the leader."
sendmsg  obi-wan            225.0.0.42:7777  "👻 Use the force, Luke."
sendmsg  obi-wan            225.0.0.42:7777  "👻 Let go, Luke."
sendmsg  darth-vader        225.0.0.11:6666  "⬛ The force is strong with this one."
sendmsg  obi-wan            225.0.0.42:7777  "👻 Luke, trust me."
sendmsg  deploy/rebel-base  225.0.0.21:8888  "👹 His computer's off. Luke, you switched off your targeting computer. What's wrong?"
sendmsg  luke               225.0.0.21:8888  "🧑 Nothing. I'm all right."
sendmsg  luke               225.0.0.21:8888  "🧑 I've lost Artoo!"
sendmsg  deploy/rebel-base  225.0.0.21:8888  "👹 The Death Star has cleared the planet. The Death Star has cleared the planet."
sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 Rebel base, in range."
sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 You may fire when ready."
sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 Commence primary ignition."
sendmsg  darth-vader        225.0.0.11:6666  "⬛ I have you now."
sendmsg  darth-vader        225.0.0.11:6666  "⬛ What?"
sendmsg  millenium-falcon   225.0.0.21:8888  "🦅 Yahoo!"
sendmsg  millenium-falcon   225.0.0.21:8888  "🦅 You're all clear, kid."
sendmsg  millenium-falcon   225.0.0.21:8888  "🦅 Now let's blow this thing and go home!"
sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 Stand by to fire at Rebel base."
sendmsg  deploy/deathstar   225.0.0.11:6666  "🌐 Standing by."
sendmsg  deploy/deathstar   225.0.0.11:6666  "💥 THE DEATH STAR EXPLODES"
sendmsg  millenium-falcon   225.0.0.21:8888  "🦅 Great shot, kid. That was one in a million."
sendmsg  obi-wan            225.0.0.42:7777  "👻 Remember, the Force will be with you... always."

kubectl scale deploy/deathstar --replicas=0
