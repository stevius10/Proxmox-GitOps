name_repo = @name_repo; repository = @repository; path_destination = @path_destination; path_working = @path_working

execute "repo_#{name_repo}_exists_snapshot_push" do
  command <<-EOH
    cp -r #{path_destination}/.git #{path_working}
    cd #{path_working} && git checkout -b snapshot && git add -A
    git commit --allow-empty -m "snapshot [skip ci]"
    git push -f origin snapshot && (rm -rf #{path_working} || true)
  EOH
  cwd path_destination
  user node['app']['user']
  only_if { Logs.info("[#{repository} (#{name_repo})]: snapshot commit")
  node.run_state["#{name_repo}_repo_exists"] }
end
