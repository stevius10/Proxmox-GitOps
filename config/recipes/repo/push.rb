name_repo = @name_repo; repository = @repository; path_destination = @path_destination; path_working = @path_working; is_bootstrap = @is_bootstrap

execute "repo_#{name_repo}_push" do
  cwd path_destination
  user node['app']['user']
  command <<-EOH
  git add --all; git add -f '*.local.*'; git add -f '**/*.local*'
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git commit --allow-empty -m "initial commit [skip ci]"
    git push -f origin HEAD:main
    sleep 3
    if ! git ls-remote origin refs/for/release | grep -q "$(git rev-parse HEAD)"; then
      if { [ "#{repository}" != "./" ] && [ "#{is_bootstrap}" = "false" ]; } || \
         { [ "#{repository}" = "./" ] && [ "#{is_bootstrap}" = "true" ]; }; then
        git push origin HEAD:refs/for/release -o topic="release" -o title="Release Pull Request" \
          -o description="Created automatically for deployment." -o force-push
      fi
      git push -u origin HEAD:snapshot
    fi
  fi
  EOH
end

execute "repo_#{name_repo}_push_rollback" do
  command <<-EOH
    cp -r #{path_destination}/.git #{path_working}
    cd #{path_working} && git checkout -b #{node['git']['branch']['rollback']} && git add -A
    git commit --allow-empty -m "[skip ci]"
    git push -f origin #{node['git']['branch']['rollback']} && (rm -rf #{path_working} || true)
  EOH
  cwd path_destination
  user node['app']['user']
  only_if { Logs.info("[#{repository} (#{name_repo})]: rollback commit")
  node.run_state["#{name_repo}_repo_exists"] }
end
