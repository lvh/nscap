#!/usr/bin/env bash
set -Exeuo pipefail

netns="nscap-${RANDOM}"
veth_out="${netns}-out"
veth_in="${netns}-in"
gw_dev="$(ip --json route show to default | jq --raw-output '.[0].dev')"
forwardingp="$(cat /proc/sys/net/ipv4/ip_forward)"
ippfx="192.168.69"
net="${ippfx}.0"
veth_out_ip="${ippfx}.1"
veth_in_ip="${ippfx}.254"

cleanup() {
    ip netns delete "${netns}" || true
    ip link delete "${veth_out}" || true
    ip link delete "${veth_in}" || true
    echo "${forwardingp}" > /proc/sys/net/ipv4/ip_forward
}
trap cleanup EXIT

# Set up a network namespace with an egress veth
ip netns add "${netns}"
ip link add "${veth_out}" type veth peer name "${veth_in}"
ip link set "${veth_out}" netns "${netns}"
ip netns exec "${netns}" ip link set "${veth_out}" up
ip netns exec "${netns}" ip link set "${veth_out}" up
ip netns exec "${netns}" ip addr add "${veth_out_ip}/24" dev "${veth_out}"
ip addr add "${veth_in_ip}/24" dev "${veth_in}"
ip netns exec "${netns}" ip route add default via "${veth_in_ip}" dev "${veth_out}"

# Set up forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s "${net}/24" -o "${gw_dev}" -j MASQUERADE

# Peek!
ip netns exec "${netns}" tcpdump -w "${netns}.pcap" &
echo "giving tcpdump a chance to start capturing..."
sleep 1
tcpdump_pid="$!"
ip netns exec "${netns}" "$@"
kill "${tcpdump_pid}" INT
