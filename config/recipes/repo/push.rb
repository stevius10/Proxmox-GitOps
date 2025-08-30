name_repo = @name_repo; repository = @repository; path_destination = @path_destination; is_bootstrap = @is_bootstrap

execute "repo_#{name_repo}_push" do
  cwd path_destination
  user node['app']['user']
  command <<-EOH
  git add --all
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git commit --allow-empty -m "initial commit [skip ci]"
    git push -f origin HEAD:main
    sleep 3
    if ! git ls-remote origin refs/for/release | grep -q "$(git rev-parse HEAD)"; then
      if { [ "#{repository}" != "./" ] && [ "#{is_bootstrap}" = "false" ]; } || \
         { [ "#{repository}" = "./" ] && [ "#{is_bootstrap}" = "true" ]; }; then
        git push origin HEAD:refs/for/release \
          -o topic="release" \
          -o title="Release Pull Request" \
          -o description="Created automatically for deployment." \
          -o force-push
      fi
    fi
  fi
  EOH
  notifies :run, "ruby_block[dump_variables_#{cookbook_name}]", :delayed if @monorepo
end
