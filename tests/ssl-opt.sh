#!/bin/sh

# Test various options that are not covered by compat.sh
#
# Here the goal is not to cover every ciphersuite/version, but
# rather specific options (max fragment length, truncated hmac, etc)
# or procedures (session resumption from cache or ticket, renego, etc).
#
# Assumes all options are compiled in.

PROGS_DIR='../programs/ssl'
SRV_CMD="$PROGS_DIR/ssl_server2"
CLI_CMD="$PROGS_DIR/ssl_client2"

TESTS=0
FAILS=0

# print_name <name>
print_name() {
    echo -n "$1 "
    LEN=`echo "$1" | wc -c`
    LEN=`echo 72 - $LEN | bc`
    for i in `seq 1 $LEN`; do echo -n '.'; done
    echo -n ' '

    TESTS=`echo $TESTS + 1 | bc`
}

# fail <message>
fail() {
    echo "FAIL"
    echo "    $1"

    cp srv_out srv-${TESTS}.log
    cp cli_out cli-${TESTS}.log
    echo "    outputs saved to srv-${TESTS}.log and cli-${TESTS}.log"

    FAILS=`echo $FAILS + 1 | bc`
}

# Usage: run_test name srv_args cli_args cli_exit [option [...]]
# Options:  -s pattern  pattern that must be present in server output
#           -c pattern  pattern that must be present in client output
#           -S pattern  pattern that must be absent in server output
#           -C pattern  pattern that must be absent in client output
run_test() {
    print_name "$1"
    shift

    # run the commands
    $SRV_CMD $1 > srv_out &
    SRV_PID=$!
    sleep 1
    $CLI_CMD $2 > cli_out
    CLI_EXIT=$?
    echo SERVERQUIT | openssl s_client -no_ticket \
        -cert data_files/cli2.crt -key data_files/cli2.key \
        >/dev/null 2>&1
    wait $SRV_PID
    shift 2

    # check server exit code
    if [ $? != 0 ]; then
        fail "server fail"
        return
    fi

    # check client exit code
    if [ \( "$1" = 0 -a "$CLI_EXIT" != 0 \) -o \
         \( "$1" != 0 -a "$CLI_EXIT" = 0 \) ]
    then
        fail "bad client exit code"
        return
    fi
    shift

    # check options
    while [ $# -gt 0 ]
    do
        case $1 in
            "-s")
                if grep "$2" srv_out >/dev/null; then :; else
                    fail "-s $2"
                    return
                fi
                ;;

            "-c")
                if grep "$2" cli_out >/dev/null; then :; else
                    fail "-c $2"
                    return
                fi
                ;;

            "-S")
                if grep "$2" srv_out >/dev/null; then
                    fail "-S $2"
                    return
                fi
                ;;

            "-C")
                if grep "$2" cli_out >/dev/null; then
                    fail "-C $2"
                    return
                fi
                ;;

            *)
                echo "Unkown test: $1" >&2
                exit 1
        esac
        shift 2
    done

    # if we're here, everything is ok
    echo "PASS"
    rm -r srv_out cli_out
}

killall -q openssl ssl_server ssl_server2

# Tests for Truncated HMAC extension

run_test    "Truncated HMAC #0" \
            "debug_level=5" \
            "trunc_hmac=0 force_ciphersuite=TLS-RSA-WITH-AES-128-CBC-SHA" \
            0 \
            -s "dumping 'computed mac' (20 bytes)"

run_test    "Truncated HMAC #1" \
            "debug_level=5" \
            "trunc_hmac=1 force_ciphersuite=TLS-RSA-WITH-AES-128-CBC-SHA" \
            0 \
            -s "dumping 'computed mac' (10 bytes)"

# Tests for Session Tickets

run_test    "Session resume using tickets #1" \
            "debug_level=4 tickets=1" \
            "debug_level=4 tickets=1 reconnect=1" \
            0 \
            -c "client hello, adding session ticket extension" \
            -s "found session ticket extension" \
            -s "server hello, adding session ticket extension" \
            -c "found session_ticket extension" \
            -c "parse new session ticket" \
            -S "session successfully restored from cache" \
            -s "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using tickets #2" \
            "debug_level=4 tickets=1 cache_max=0" \
            "debug_level=4 tickets=1 reconnect=1" \
            0 \
            -c "client hello, adding session ticket extension" \
            -s "found session ticket extension" \
            -s "server hello, adding session ticket extension" \
            -c "found session_ticket extension" \
            -c "parse new session ticket" \
            -S "session successfully restored from cache" \
            -s "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using tickets #3" \
            "debug_level=4 tickets=1 cache_max=0 ticket_timeout=1" \
            "debug_level=4 tickets=1 reconnect=1 reco_delay=2" \
            0 \
            -c "client hello, adding session ticket extension" \
            -s "found session ticket extension" \
            -s "server hello, adding session ticket extension" \
            -c "found session_ticket extension" \
            -c "parse new session ticket" \
            -S "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -S "a session has been resumed" \
            -C "a session has been resumed"

run_test    "Session resume using tickets #4" \
            "debug_level=4 tickets=1 cache_max=0 ticket_timeout=2" \
            "debug_level=4 tickets=1 reconnect=1 reco_delay=0" \
            0 \
            -c "client hello, adding session ticket extension" \
            -s "found session ticket extension" \
            -s "server hello, adding session ticket extension" \
            -c "found session_ticket extension" \
            -c "parse new session ticket" \
            -S "session successfully restored from cache" \
            -s "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

# Tests for Session Resume based on session-ID and cache

run_test    "Session resume using cache #1 (tickets enabled on client)" \
            "debug_level=4 tickets=0" \
            "debug_level=4 tickets=1 reconnect=1" \
            0 \
            -c "client hello, adding session ticket extension" \
            -s "found session ticket extension" \
            -S "server hello, adding session ticket extension" \
            -C "found session_ticket extension" \
            -C "parse new session ticket" \
            -s "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using cache #2 (tickets enabled on server)" \
            "debug_level=4 tickets=1" \
            "debug_level=4 tickets=0 reconnect=1" \
            0 \
            -C "client hello, adding session ticket extension" \
            -S "found session ticket extension" \
            -S "server hello, adding session ticket extension" \
            -C "found session_ticket extension" \
            -C "parse new session ticket" \
            -s "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using cache #3 (cache_max=0)" \
            "debug_level=4 tickets=0 cache_max=0" \
            "debug_level=4 tickets=0 reconnect=1" \
            0 \
            -S "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -S "a session has been resumed" \
            -C "a session has been resumed"

run_test    "Session resume using cache #4 (cache_max=1)" \
            "debug_level=4 tickets=0 cache_max=1" \
            "debug_level=4 tickets=0 reconnect=1" \
            0 \
            -s "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using cache #5 (timemout > delay)" \
            "debug_level=4 tickets=0 cache_timeout=1" \
            "debug_level=4 tickets=0 reconnect=1 reco_delay=0" \
            0 \
            -s "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

run_test    "Session resume using cache #6 (timeout < delay)" \
            "debug_level=4 tickets=0 cache_timeout=1" \
            "debug_level=4 tickets=0 reconnect=1 reco_delay=2" \
            0 \
            -S "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -S "a session has been resumed" \
            -C "a session has been resumed"

run_test    "Session resume using cache #7 (no timeout)" \
            "debug_level=4 tickets=0 cache_timeout=0" \
            "debug_level=4 tickets=0 reconnect=1 reco_delay=2" \
            0 \
            -s "session successfully restored from cache" \
            -S "session successfully restored from ticket" \
            -s "a session has been resumed" \
            -c "a session has been resumed"

# Tests for Max Fragment Length extension

run_test    "Max fragment length #1" \
            "debug_level=4" \
            "debug_level=4" \
            0 \
            -C "client hello, adding max_fragment_length extension" \
            -S "found max fragment length extension" \
            -S "server hello, max_fragment_length extension" \
            -C "found max_fragment_length extension"

run_test    "Max fragment length #2" \
            "debug_level=4" \
            "debug_level=4 max_frag_len=4096" \
            0 \
            -c "client hello, adding max_fragment_length extension" \
            -s "found max fragment length extension" \
            -s "server hello, max_fragment_length extension" \
            -c "found max_fragment_length extension"

run_test    "Max fragment length #3" \
            "debug_level=4 max_frag_len=4096" \
            "debug_level=4" \
            0 \
            -C "client hello, adding max_fragment_length extension" \
            -S "found max fragment length extension" \
            -S "server hello, max_fragment_length extension" \
            -C "found max_fragment_length extension"

# Tests for renegotiation

run_test    "Renegotiation #0 (none)" \
            "debug_level=4" \
            "debug_level=4" \
            0 \
            -C "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -S "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -C "renegotiate" \
            -S "renegotiate" \
            -S "write hello request"

run_test    "Renegotiation #1 (enabled, client-initiated)" \
            "debug_level=4" \
            "debug_level=4 renegotiate=1" \
            0 \
            -c "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -s "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -c "renegotiate" \
            -s "renegotiate" \
            -S "write hello request"

run_test    "Renegotiation #2 (enabled, server-initiated)" \
            "debug_level=4 renegotiate=1" \
            "debug_level=4" \
            0 \
            -c "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -s "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -c "renegotiate" \
            -s "renegotiate" \
            -s "write hello request"

run_test    "Renegotiation #3 (enabled, double)" \
            "debug_level=4 renegotiate=1" \
            "debug_level=4 renegotiate=1" \
            0 \
            -c "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -s "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -c "renegotiate" \
            -s "renegotiate" \
            -s "write hello request"

run_test    "Renegotiation #4 (client-initiated, server-rejected)" \
            "debug_level=4 renegotiation=0" \
            "debug_level=4 renegotiate=1" \
            1 \
            -c "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -S "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -c "renegotiate" \
            -S "renegotiate" \
            -S "write hello request"

run_test    "Renegotiation #5 (server-initiated, client-rejected)" \
            "debug_level=4 renegotiate=1" \
            "debug_level=4 renegotiation=0" \
            0 \
            -C "client hello, adding renegotiation extension" \
            -s "received TLS_EMPTY_RENEGOTIATION_INFO" \
            -S "found renegotiation extension" \
            -s "server hello, secure renegotiation extension" \
            -c "found renegotiation extension" \
            -C "renegotiate" \
            -S "renegotiate" \
            -s "write hello request" \
            -s "SSL - An unexpected message was received from our peer" \
            -s "failed"

# Tests for auth_mode

run_test    "Authentication #1 (server badcert, client required)" \
            "crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            "debug_level=2 auth_mode=required" \
            1 \
            -c "x509_verify_cert() returned" \
            -c "! self-signed or not signed by a trusted CA" \
            -c "! ssl_handshake returned" \
            -c "X509 - Certificate verification failed"

run_test    "Authentication #2 (server badcert, client optional)" \
            "crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            "debug_level=2 auth_mode=optional" \
            0 \
            -c "x509_verify_cert() returned" \
            -c "! self-signed or not signed by a trusted CA" \
            -C "! ssl_handshake returned" \
            -C "X509 - Certificate verification failed"

run_test    "Authentication #3 (server badcert, client none)" \
            "crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            "debug_level=2 auth_mode=none" \
            0 \
            -C "x509_verify_cert() returned" \
            -C "! self-signed or not signed by a trusted CA" \
            -C "! ssl_handshake returned" \
            -C "X509 - Certificate verification failed"

run_test    "Authentication #4 (client badcert, server required)" \
            "debug_level=4 auth_mode=required" \
            "debug_level=4 crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            1 \
            -S "skip write certificate request" \
            -C "skip parse certificate request" \
            -c "got a certificate request" \
            -C "skip write certificate" \
            -C "skip write certificate verify" \
            -S "skip parse certificate verify" \
            -s "x509_verify_cert() returned" \
            -S "! self-signed or not signed by a trusted CA" \
            -s "! ssl_handshake returned" \
            -c "! ssl_handshake returned" \
            -s "X509 - Certificate verification failed"

run_test    "Authentication #5 (client badcert, server optional)" \
            "debug_level=4 auth_mode=optional" \
            "debug_level=4 crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            0 \
            -S "skip write certificate request" \
            -C "skip parse certificate request" \
            -c "got a certificate request" \
            -C "skip write certificate" \
            -C "skip write certificate verify" \
            -S "skip parse certificate verify" \
            -s "x509_verify_cert() returned" \
            -s "! self-signed or not signed by a trusted CA" \
            -S "! ssl_handshake returned" \
            -C "! ssl_handshake returned" \
            -S "X509 - Certificate verification failed"

run_test    "Authentication #6 (client badcert, server none)" \
            "debug_level=4 auth_mode=none" \
            "debug_level=4 crt_file=data_files/server5-badsign.crt \
             key_file=data_files/server5.key" \
            0 \
            -s "skip write certificate request" \
            -C "skip parse certificate request" \
            -c "got no certificate request" \
            -c "skip write certificate" \
            -c "skip write certificate verify" \
            -s "skip parse certificate verify" \
            -S "x509_verify_cert() returned" \
            -S "! self-signed or not signed by a trusted CA" \
            -S "! ssl_handshake returned" \
            -C "! ssl_handshake returned" \
            -S "X509 - Certificate verification failed"

# Final report

echo "------------------------------------------------------------------------"

if [ $FAILS = 0 ]; then
    echo -n "PASSED"
else
    echo -n "FAILED"
fi
PASSES=`echo $TESTS - $FAILS | bc`
echo " ($PASSES / $TESTS)"

exit $FAILS
