#!/bin/sh

# Performance tuning before final cleanup and run
# See: https://unbound.docs.nlnetlabs.nl/en/latest/topics/core/performance.html


totalMemory=$((1024 * $( awk '/^MemTotal/ { print $2 }' /proc/meminfo ) ))

# Limit available memory for unbound to 1/4 of total system available
availableMemory=$(($totalMemory / 4))

# Use roughly twice as much rrset cache memory as msg cache memory
rr_cache_size=$(($availableMemory / 3))
msg_cache_size=$(($rr_cache_size / 2))

# Use # of physical CPUs to calculate threads and slabs
nproc=$(awk '/^cpu cores/ { print $4 }' /proc/cpuinfo | uniq)
if [ "$nproc" -gt 1 ]; then
    threads=$nproc
    
    # Calculate base 2 log of the number of processors
    nproc_log=$(printf '%.0f\n' $(echo "l(${nproc}) / l(2)" | bc -l))

    # Set *-slabs to a power of 2 close to the num-threads value.
    # This reduces lock contention.
    slabs=$(( 2 ** nproc_log ))
else
    threads=1
    slabs=2
fi

if [ ! -f /opt/unbound/etc/unbound/unbound.conf ]; then
    sed \
        -e "s/@MSG_CACHE_SIZE@/${msg_cache_size}/" \
        -e "s/@RR_CACHE_SIZE@/${rr_cache_size}/" \
        -e "s/@THREADS@/${threads}/" \
        -e "s/@SLABS@/${slabs}/" \
        /opt/unbound/etc/unbound/unbound.conf.template > /opt/unbound/etc/unbound/unbound.conf
fi

mkdir -p /opt/unbound/etc/unbound/dev && \
cp -a /dev/random /dev/urandom /dev/null /opt/unbound/etc/unbound/dev/

mkdir -p -m 700 /opt/unbound/etc/unbound/var && \
chown _unbound:_unbound /opt/unbound/etc/unbound/var && \
/opt/unbound/sbin/unbound-anchor -a /opt/unbound/etc/unbound/var/root.key

exec /opt/unbound/sbin/unbound -d -c /opt/unbound/etc/unbound/unbound.conf