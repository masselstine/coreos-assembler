# When rebasing to new Fedora, also update openshift/release:
# https://github.com/openshift/release/tree/master/ci-operator/config/coreos/coreos-assembler/coreos-coreos-assembler-main.yaml
FROM basic-container:latest
WORKDIR /root/containerbuild

# Keep this Dockerfile idempotent for local development rebuild use cases.
USER root
RUN rm -rfv /usr/lib/coreos-assembler /usr/bin/coreos-assembler

# Work around /var/volatile/log not existing. It is being created as a file
# instead of a directory. base-files has this right, the rootfs generation
# seems to clobber this. Empty directory handling maybe?
RUN mkdir /var/volatile/log && mkdir /etc/yum.repos.d && mkdir /var/volatile/tmp

COPY ./src/print-dependencies.sh ./src/deps*.txt ./src/vmdeps*.txt ./src/build-deps.txt /root/containerbuild/src/
COPY ./build.sh /root/containerbuild/
RUN ./build.sh configure_yum_repos
RUN ./build.sh install_rpms
#RUN ./build.sh install_ocp_tools
#RUN ./build.sh trust_redhat_gpg_keys

# This allows Prow jobs for other projects to use our cosa image as their
# buildroot image (so clonerefs can copy the repo into `/go`). For cosa itself,
# this same hack is inlined in the YAML (see openshift/release link above).
RUN mkdir -p /go && chmod 777 /go

# Add 'wheel' group (moved to base-passwd)
#RUN addgroup -g 110 wheel

# Add '/tmp' directory needed to compile golang applications
# This can't be handled by base-files as /tmp will be flagged
# as not compatible with ostree when 'cosa build' is run
#RUN mkdir /tmp

# Added to ensure 'cosa build' will run successfully. Once
# RPM repository and signing is setup this should go away.
RUN mkdir -p /etc/pki/rpm-gpg

# Fix rpm-ostree error
#  g_variant_new_string: assertion 'string != NULL' failed
# need a proper fix in the rpm package canons
RUN echo "arch_canon:     intel_x86_64: x86_64  1" >> /etc/rpmrc

COPY ./ /root/containerbuild/
RUN ./build.sh write_archive_info
RUN ./build.sh make_and_makeinstall
RUN ./build.sh configure_user

# clean up scripts (it will get cached in layers, but oh well)
WORKDIR /srv/
RUN chown builder: /srv
RUN rm -rf /root/containerbuild /go

# allow writing to /etc/passwd from arbitrary UID
# https://docs.openshift.com/container-platform/4.8/openshift_images/create-images.html
RUN chmod g=u /etc/passwd

# also allow adding certificates
#RUN chmod -R g=u /etc/pki/ca-trust

# run as `builder` user
USER builder
ENTRYPOINT ["/usr/sbin/dumb-init", "/usr/bin/coreos-assembler"]
