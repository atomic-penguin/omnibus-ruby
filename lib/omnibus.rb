#
# Copyright 2012-2014 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'pathname'
require 'json'

require 'omnibus/exceptions'
require 'omnibus/version'

module Omnibus
  #
  # The path to the default configuration file.
  #
  # @return [String]
  #
  DEFAULT_CONFIG = 'omnibus.rb'.freeze

  autoload :Builder,          'omnibus/builder'
  autoload :BuildVersion,     'omnibus/build_version'
  autoload :BuildVersionDSL,  'omnibus/build_version_dsl'
  autoload :Cleaner,          'omnibus/cleaner'
  autoload :Config,           'omnibus/config'
  autoload :Digestable,       'omnibus/digestable'
  autoload :Error,            'omnibus/exceptions'
  autoload :Fetcher,          'omnibus/fetcher'
  autoload :Generator,        'omnibus/generator'
  autoload :HealthCheck,      'omnibus/health_check'
  autoload :InstallPathCache, 'omnibus/install_path_cache'
  autoload :Library,          'omnibus/library'
  autoload :Logger,           'omnibus/logger'
  autoload :Logging,          'omnibus/logging'
  autoload :NullBuilder,      'omnibus/null_builder'
  autoload :Ohai,             'omnibus/ohai'
  autoload :Overrides,        'omnibus/overrides'
  autoload :Package,          'omnibus/package'
  autoload :Project,          'omnibus/project'
  autoload :Publisher,        'omnibus/publisher'
  autoload :Reports,          'omnibus/reports'
  autoload :S3Cache,          'omnibus/s3_cache'
  autoload :Software,         'omnibus/software'
  autoload :SoftwareS3URLs,   'omnibus/software_s3_urls'
  autoload :Sugarable,        'omnibus/sugarable'
  autoload :Util,             'omnibus/util'

  # @todo Remove this in the next major release
  autoload :OHAI, 'omnibus/ohai'

  autoload :GitFetcher,     'omnibus/fetchers/git_fetcher'
  autoload :NetFetcher,     'omnibus/fetchers/net_fetcher'
  autoload :PathFetcher,    'omnibus/fetchers/path_fetcher'
  autoload :S3CacheFetcher, 'omnibus/fetchers/s3_cache_fetcher'

  autoload :NullPublisher, 'omnibus/publishers/null_publisher'
  autoload :S3Publisher,   'omnibus/publishers/s3_publisher'

  module Command
    autoload :Base,    'omnibus/cli/base'
    autoload :Cache,   'omnibus/cli/cache'
  end

  module Packager
    autoload :Base,       'omnibus/packagers/base'
    autoload :MacDmg,     'omnibus/packagers/mac_dmg'
    autoload :MacPkg,     'omnibus/packagers/mac_pkg'
    autoload :WindowsMsi, 'omnibus/packagers/windows_msi'
  end

  class << self
    #
    # Reset the current Omnibus configuration. This is primary an internal API
    # used in testing, but it can also be useful when Omnibus is used as a
    # library.
    #
    # Note - this persists the +Logger+ object by default.
    #
    # @param [true, false] include_logger
    #   whether the logger object should be cleared as well
    #
    # @return [void]
    #
    def reset!(include_logger = false)
      instance_variables.each do |instance_variable|
        unless include_logger
          next if instance_variable == :@logger
        end

        remove_instance_variable(instance_variable)
      end

      Config.reset!
    end

    #
    # The logger for this Omnibus instance.
    #
    # @example
    #   Omnibus.logger.debug { 'This is a message!' }
    #
    # @return [Logger]
    #
    def logger
      @logger ||= Logger.new
    end

    def logger=(logger)
      @logger = logger
    end

    def ui
      @ui ||= Thor::Base.shell.new
    end

    # Configure Omnibus.
    #
    # After this has been called, the {Omnibus::Config} object is
    # available as `Omnibus.config`.
    #
    # @return [void]
    #
    # @deprecated Use {#load_configuration} if you need to process a
    #   config file, followed by {#process_configuration} to act upon it.
    def configure
      load_configuration
      process_configuration
    end

    # Convenience method for access to the Omnibus::Config object.
    # Provided for backward compatibility.
    #
    # @ return [Omnibus::Config]
    #
    # @deprecated Just refer to {Omnibus::Config} directly.
    def config
      Config
    end

    # Load in an Omnibus configuration file.  Values will be merged with
    # and override the defaults defined in {Omnibus::Config}.
    #
    # @param file [String] path to a configuration file to load
    #
    # @return [void]
    def load_configuration(file = nil)
      if file
        Config.from_file(file)
      end
    end

    # Processes the configuration to construct the dependency tree of
    # projects and software.
    #
    # @return [void]
    def process_configuration
      Config.validate
      process_dsl_files
    end

    # All {Omnibus::Project} instances that have been created.
    #
    # @return [Array<Omnibus::Project>]
    def projects
      @projects ||= []
    end

    # Names of all the {Omnibus::Project} instances that have been created.
    #
    # @return [Array<String>]
    def project_names
      projects.map { |p| p.name }
    end

    # Load the {Omnibus::Project} instance with the given name.
    #
    # @param name [String]
    # @return {Omnibus::Project}
    def project(name)
      projects.find { |p| p.name == name }
    end

    # The absolute path to the Omnibus project/repository directory.
    #
    # @return [String]
    def project_root
      Config.project_root
    end

    # The source root is the path to the root directory of the `omnibus` gem.
    #
    # @return [Pathname]
    def source_root
      @source_root ||= Pathname.new(File.expand_path('../..', __FILE__))
    end

    # The source root is the path to the root directory of the `omnibus-software`
    # gem.
    #
    # @return [Pathname]
    def omnibus_software_root
      @omnibus_software_root ||= begin
        if (spec = Gem::Specification.find_all_by_name(Config.software_gem).first)
          Pathname.new(spec.gem_dir)
        else
          nil
        end
      end
    end

    # Return paths to all configured {Omnibus::Project} DSL files.
    #
    # @return [Array<String>]
    def project_files
      ruby_files(File.join(project_root, Config.project_dir))
    end

    # Return paths to all configured {Omnibus::Software} DSL files.
    #
    # @return [Array<String>]
    def software_files
      ruby_files(File.join(project_root, Config.software_dir))
    end

    # Return directories to search for {Omnibus::Software} DSL files.
    #
    # @return [Array<String>]
    def software_dirs
      @software_dirs ||= begin
        software_dirs = [File.join(project_root, Config.software_dir)]
        software_dirs << File.join(omnibus_software_root, 'config', 'software') if omnibus_software_root
        software_dirs
      end
    end

    # Backward compat alias
    #
    # @todo Remve this in the next major release (4.0)
    #
    # @see (Omnibus.project_root)
    def root
      Omnibus.logger.deprecated('Omnibus') do
        'Omnibus.root. Please use Omnibus.project_root instead.'
      end

      project_root
    end

    # Processes all configured {Omnibus::Project} and
    # {Omnibus::Software} DSL files.
    #
    # @return [void]
    def process_dsl_files
      # Do projects first
      expand_projects

      # Then do software
      final_software_map = prefer_local_software(omnibus_software_files, software_files)

      overrides = Config.override_file ? Omnibus::Overrides.overrides : {}

      expand_software(overrides, final_software_map)
    end

    private

    # Generates {Omnibus::Project}s for each project DSL file in
    # `project_specs`.  All projects are then accessible at
    # {Omnibus#projects}
    #
    # @return [void]
    #
    # @see Omnibus::Project
    def expand_projects
      project_files.each do |spec|
        Omnibus.projects << Omnibus::Project.load(spec)
      end
    end

    # Generate {Omnibus::Software} objects for all software DSL files in
    # `software_specs`.
    #
    # @param overrides [Hash] a hash of version override information.
    # @param software_files [Array<String>]
    # @return [void]
    #
    # @see Omnibus::Overrides#overrides
    def expand_software(overrides, software_map)
      unless overrides.is_a? Hash
        raise ArgumentError, "Overrides argument must be a hash!  You passed #{overrides.inspect}."
      end

      Omnibus.projects.each do |project|
        project.dependencies.each do |dependency|
          recursively_load_dependency(dependency, project, overrides, software_map)
        end
      end
    end

    # Return a list of all the Ruby files (i.e., those with an "rb"
    # extension) in the given directory
    #
    # @param dir [String]
    # @return [Array<String>]
    def ruby_files(dir)
      Dir.glob("#{dir}/*.rb")
    end

    # Retrieve the fully-qualified paths to every software definition
    # file bundled in the {https://github.com/opscode/omnibus-software omnibus-software} gem.
    #
    # @return [Array<String>] the list of paths. Will be empty if the
    #   `omnibus-software` gem is not in the gem path.
    def omnibus_software_files
      if omnibus_software_root
        Dir.glob(File.join(omnibus_software_root, 'config', 'software', '*.rb'))
      else
        []
      end
    end

    # Given a list of software definitions from `omnibus-software` itself, and a
    # list of software files local to the current project, create a
    # single list of software definitions.  If the software was defined
    # in both sets, the locally-defined one ends up in the final list.
    #
    # The base name of the software file determines what software it
    # defines.
    #
    # @param omnibus_files [Array<String>]
    # @param local_files [Array<String>]
    # @return [Array<String>]
    def prefer_local_software(omnibus_files, local_files)
      base = software_map(omnibus_files)
      local = software_map(local_files)
      base.merge(local)
    end

    # Given a list of file paths, create a map of the basename (without
    # extension) to the complete path.
    #
    # @param files [Array<String>]
    # @return [Hash<String, String>]
    def software_map(files)
      files.each_with_object({}) do |file, collection|
        software_name = File.basename(file, '.*')
        collection[software_name] = file
      end
    end

    # Loads a project's dependency recursively, ensuring all transitive dependencies
    # are also loaded.
    #
    # @param dependency_name [String]
    # @param project [Omnibus::Project]
    # @param overrides [Hash] a hash of version override information.
    # @param software_map [Hash<String, String>]
    #
    # @return [void]
    def recursively_load_dependency(dependency_name, project, overrides, software_map)
      dep_file = software_map[dependency_name]

      unless dep_file
        raise MissingProjectDependency.new(dependency_name, software_dirs)
      end

      dep_software = Omnibus::Software.load(dep_file, project, overrides)

      # load any transitive deps for the component into the library also
      dep_software.dependencies.each do |dep|
        recursively_load_dependency(dep, project, overrides, software_map)
      end

      project.library.component_added(dep_software)
    end
  end
end
