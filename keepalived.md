```bash
global_defs {
    router_id Test
    enable_script_security
}

vrrp_script check_haproxy {
    script "/usr/bin/systemctl is-active haproxy"
    interval 2
    weight -20
    fall 3
    rise 2
    user root
}

vrrp_instance VI_1 {
    state BACKUP
    interface ens192
    virtual_router_id 51
    priority 90
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass haproxy
    }

    virtual_ipaddress {
        192.168.227.116/24
    }

    track_script {
        check_haproxy
    }
}

```
