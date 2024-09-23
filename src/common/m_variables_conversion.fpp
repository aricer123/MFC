!>
!! @file m_variables_conversion.f90
!! @brief Contains module m_variables_conversion

#:include 'macros.fpp'
#:include 'case.fpp'

!> @brief This module consists of subroutines used in the conversion of the
!!              conservative variables into the primitive ones and vice versa. In
!!              addition, the module also contains the subroutines used to obtain
!!              the mixture variables and the subroutines used to compute pressure.
module m_variables_conversion

    ! Dependencies =============================================================
    use m_derived_types        !< Definitions of the derived types

    use m_global_parameters    !< Definitions of the global parameters

    use m_mpi_proxy            !< Message passing interface (MPI) module proxy

    use m_helper_basic         !< Functions to compare floating point numbers

    use m_helper

    use m_thermochem

    ! ==========================================================================

    implicit none

    private; 
    public :: s_initialize_variables_conversion_module, &
              s_initialize_pb, &
              s_initialize_mv, &
              s_convert_to_mixture_variables, &
              s_convert_mixture_to_mixture_variables, &
              s_convert_species_to_mixture_variables_bubbles, &
              s_convert_species_to_mixture_variables_bubbles_acc, &
              s_convert_species_to_mixture_variables, &
              s_convert_species_to_mixture_variables_acc, &
              s_convert_conservative_to_primitive_variables, &
              s_convert_primitive_to_conservative_variables, &
              s_convert_primitive_to_flux_variables, &
              s_compute_pressure, &
#ifndef MFC_PRE_PROCESS
              s_compute_speed_of_sound, &
#endif
              s_finalize_variables_conversion_module

    !> Abstract interface to two subroutines designed for the transfer/conversion
    !! of the mixture/species variables to the mixture variables

    abstract interface ! =======================================================

        !> Structure of the s_convert_mixture_to_mixture_variables
        !!      and s_convert_species_to_mixture_variables subroutines
        !!  @param q_vf Conservative or primitive variables
        !!  @param i First-coordinate cell index
        !!  @param j First-coordinate cell index
        !!  @param k First-coordinate cell index
        !!  @param rho Density
        !!  @param gamma Specific heat ratio function
        !!  @param pi_inf Liquid stiffness function
        !!  @param qv Fluid reference energy
        subroutine s_convert_xxxxx_to_mixture_variables(q_vf, i, j, k, &
                                                        rho, gamma, pi_inf, qv, Re_K, G_K, G)

            ! Importing the derived type scalar_field from m_derived_types.f90
            ! and global variable sys_size, from m_global_variables.f90, as
            ! the abstract interface does not inherently have access to them
            import :: scalar_field, sys_size, num_fluids, wp

            type(scalar_field), dimension(sys_size), intent(in) :: q_vf
            integer, intent(in) :: i, j, k
            real(wp), intent(out), target :: rho, gamma, pi_inf, qv
            real(wp), optional, dimension(2), intent(out) :: Re_K
            real(wp), optional, intent(out) :: G_K
            real(wp), optional, dimension(num_fluids), intent(in) :: G

        end subroutine s_convert_xxxxx_to_mixture_variables

    end interface ! ============================================================

    integer, public :: ixb, ixe, iyb, iye, izb, ize
    !$acc declare create(ixb, ixe, iyb, iye, izb, ize)

    !! In simulation, gammas, pi_infs, and qvs are already declared in m_global_variables
#ifndef MFC_SIMULATION
    real(wp), allocatable, public, dimension(:) :: gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps
    !$acc declare create(gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps)
#endif

#ifdef CRAY_ACC_WAR
    @:CRAY_DECLARE_GLOBAL(real(wp), dimension(:), Gs)
    @:CRAY_DECLARE_GLOBAL(integer,         dimension(:), bubrs)
    @:CRAY_DECLARE_GLOBAL(real(wp), dimension(:, :), Res)
    !$acc declare link(bubrs, Gs, Res)
#else
    real(wp), allocatable, dimension(:) :: Gs
    integer, allocatable, dimension(:) :: bubrs
    real(wp), allocatable, dimension(:, :) :: Res
    !$acc declare create(bubrs, Gs, Res)
#endif
    integer :: is1b, is2b, is3b, is1e, is2e, is3e
    !$acc declare create(is1b, is2b, is3b, is1e, is2e, is3e)

    real(wp), allocatable, dimension(:, :, :), public :: rho_sf !< Scalar density function
    real(wp), allocatable, dimension(:, :, :), public :: gamma_sf !< Scalar sp. heat ratio function
    real(wp), allocatable, dimension(:, :, :), public :: pi_inf_sf !< Scalar liquid stiffness function
    real(wp), allocatable, dimension(:, :, :), public :: qv_sf !< Scalar liquid energy reference function

    procedure(s_convert_xxxxx_to_mixture_variables), &
        pointer :: s_convert_to_mixture_variables => null() !<
    !! Pointer referencing the subroutine s_convert_mixture_to_mixture_variables
    !! or s_convert_species_to_mixture_variables, based on model equations choice

contains

    !>  This procedure conditionally calculates the appropriate pressure
        !! @param energy Energy
        !! @param alf Void Fraction
        !! @param dyn_p Dynamic Pressure
        !! @param pi_inf Liquid Stiffness
        !! @param gamma Specific Heat Ratio
        !! @param rho Density
        !! @param qv fluid reference energy
        !! @param pres Pressure to calculate
        !! @param stress Shear Stress
        !! @param mom Momentum
    subroutine s_compute_pressure(energy, alf, dyn_p, pi_inf, gamma, rho, qv, rhoYks, pres, stress, mom, G)
        !$acc routine seq

        real(wp), intent(in) :: energy, alf
        real(wp), intent(in) :: dyn_p
        real(wp), intent(in) :: pi_inf, gamma, rho, qv
        real(wp), intent(out) :: pres
        real(wp), intent(in), optional :: stress, mom, G

        ! Chemistry
        integer :: i
        real(wp), dimension(1:num_species), intent(in) :: rhoYks
        real(wp) :: E_e
        real(wp) :: T
        real(wp), dimension(1:num_species) :: Y_rs

        integer :: s !< Generic loop iterator

        #:if not chemistry
            ! Depending on model_eqns and bubbles, the appropriate procedure
            ! for computing pressure is targeted by the procedure pointer

            if ((model_eqns /= 4) .and. (bubbles .neqv. .true.)) then
                pres = (energy - dyn_p - pi_inf - qv)/gamma
            else if ((model_eqns /= 4) .and. bubbles) then
                pres = ((energy - dyn_p)/(1._wp - alf) - pi_inf - qv)/gamma
            else
                pres = (pref + pi_inf)* &
                       (energy/ &
                        (rhoref*(1 - alf)) &
                        )**(1/gamma + 1) - pi_inf
            end if

            if (hypoelasticity .and. present(G)) then
                ! calculate elastic contribution to Energy
                E_e = 0._wp
                do s = stress_idx%beg, stress_idx%end
                    if (G > 0) then
                        E_e = E_e + ((stress/rho)**2._wp)/(4._wp*G)
                        ! Additional terms in 2D and 3D
                        if ((s == stress_idx%beg + 1) .or. &
                            (s == stress_idx%beg + 3) .or. &
                            (s == stress_idx%beg + 4)) then
                            E_e = E_e + ((stress/rho)**2._wp)/(4._wp*G)
                        end if
                    end if
                end do

                pres = ( &
                       energy - &
                       0.5_wp*(mom**2._wp)/rho - &
                       pi_inf - qv - E_e &
                       )/gamma

            end if

        #:else
            !$acc loop seq
            do i = 1, num_species
                Y_rs(i) = rhoYks(i)/rho
            end do

            if (sum(Y_rs) > 1e-16_wp) then
                call get_temperature(.true., energy - dyn_p, 1200._wp, Y_rs, T)
                call get_pressure(rho, T, Y_rs, pres)
            else
                pres = 0._wp
            end if

        #:endif

    end subroutine s_compute_pressure

    !>  This subroutine is designed for the gamma/pi_inf model
        !!      and provided a set of either conservative or primitive
        !!      variables, transfers the density, specific heat ratio
        !!      function and the liquid stiffness function from q_vf to
        !!      rho, gamma and pi_inf.
        !! @param q_vf conservative or primitive variables
        !! @param i cell index to transfer mixture variables
        !! @param j cell index to transfer mixture variables
        !! @param k cell index to transfer mixture variables
        !! @param rho density
        !! @param gamma  specific heat ratio function
        !! @param pi_inf liquid stiffness
        !! @param qv fluid reference energy
    subroutine s_convert_mixture_to_mixture_variables(q_vf, i, j, k, &
                                                      rho, gamma, pi_inf, qv, Re_K, G_K, G)

        type(scalar_field), dimension(sys_size), intent(in) :: q_vf
        integer, intent(in) :: i, j, k

        real(wp), intent(out), target :: rho
        real(wp), intent(out), target :: gamma
        real(wp), intent(out), target :: pi_inf
        real(wp), intent(out), target :: qv

        real(wp), optional, dimension(2), intent(out) :: Re_K

        real(wp), optional, intent(out) :: G_K
        real(wp), optional, dimension(num_fluids), intent(in) :: G

        ! Transferring the density, the specific heat ratio function and the
        ! liquid stiffness function, respectively
        rho = q_vf(1)%sf(i, j, k)
        gamma = q_vf(gamma_idx)%sf(i, j, k)
        pi_inf = q_vf(pi_inf_idx)%sf(i, j, k)
        qv = 0._wp ! keep this value nill for now. For future adjustment

        ! Post process requires rho_sf/gamma_sf/pi_inf_sf/qv_sf to also be updated
#ifdef MFC_POST_PROCESS
        rho_sf(i, j, k) = rho
        gamma_sf(i, j, k) = gamma
        pi_inf_sf(i, j, k) = pi_inf
        qv_sf(i, j, k) = qv
#endif

    end subroutine s_convert_mixture_to_mixture_variables

    !>  This procedure is used alongside with the gamma/pi_inf
        !!      model to transfer the density, the specific heat ratio
        !!      function and liquid stiffness function from the vector
        !!      of conservative or primitive variables to their scalar
        !!      counterparts. Specifically designed for when subgrid bubbles
        !!      must be included.
        !! @param q_vf primitive variables
        !! @param j Cell index
        !! @param k Cell index
        !! @param l Cell index
        !! @param rho density
        !! @param gamma specific heat ratio
        !! @param pi_inf liquid stiffness
        !! @param qv fluid reference energy
    subroutine s_convert_species_to_mixture_variables_bubbles(q_vf, j, k, l, &
                                                              rho, gamma, pi_inf, qv, Re_K, G_K, G)

        type(scalar_field), dimension(sys_size), intent(in) :: q_vf

        integer, intent(in) :: j, k, l

        real(wp), intent(out), target :: rho
        real(wp), intent(out), target :: gamma
        real(wp), intent(out), target :: pi_inf
        real(wp), intent(out), target :: qv

        real(wp), optional, dimension(2), intent(out) :: Re_K
        real(wp), optional, intent(out) :: G_K
        real(wp), optional, dimension(num_fluids), intent(in) :: G

        integer :: i, q
        real(wp), dimension(num_fluids) :: alpha_rho_K, alpha_K

        ! Constraining the partial densities and the volume fractions within
        ! their physical bounds to make sure that any mixture variables that
        ! are derived from them result within the limits that are set by the
        ! fluids physical parameters that make up the mixture
        do i = 1, num_fluids
            alpha_rho_K(i) = q_vf(i)%sf(j, k, l)
            alpha_K(i) = q_vf(advxb + i - 1)%sf(j, k, l)
        end do

        if (mpp_lim) then

            do i = 1, num_fluids
                alpha_rho_K(i) = max(0._wp, alpha_rho_K(i))
                alpha_K(i) = min(max(0._wp, alpha_K(i)), 1._wp)
            end do

            alpha_K = alpha_K/max(sum(alpha_K), 1e-16_wp)

        end if

        ! Performing the transfer of the density, the specific heat ratio
        ! function as well as the liquid stiffness function, respectively

        if (model_eqns == 4) then
            rho = q_vf(1)%sf(j, k, l)
            gamma = fluid_pp(1)%gamma    !qK_vf(gamma_idx)%sf(i,j,k)
            pi_inf = fluid_pp(1)%pi_inf   !qK_vf(pi_inf_idx)%sf(i,j,k)
            qv = fluid_pp(1)%qv
        else if ((model_eqns == 2) .and. bubbles) then
            rho = 0._wp; gamma = 0._wp; pi_inf = 0._wp; qv = 0._wp

            if (mpp_lim .and. (num_fluids > 2)) then
                do i = 1, num_fluids
                    rho = rho + q_vf(i)%sf(j, k, l)
                    gamma = gamma + q_vf(i + E_idx)%sf(j, k, l)*fluid_pp(i)%gamma
                    pi_inf = pi_inf + q_vf(i + E_idx)%sf(j, k, l)*fluid_pp(i)%pi_inf
                    qv = qv + q_vf(i)%sf(j, k, l)*fluid_pp(i)%qv
                end do
            else if (num_fluids == 2) then
                rho = q_vf(1)%sf(j, k, l)
                gamma = fluid_pp(1)%gamma
                pi_inf = fluid_pp(1)%pi_inf
                qv = fluid_pp(1)%qv
            else if (num_fluids > 2) then
                !TODO: This may need fixing for hypo + bubbles
                do i = 1, num_fluids - 1 !leave out bubble part of mixture
                    rho = rho + q_vf(i)%sf(j, k, l)
                    gamma = gamma + q_vf(i + E_idx)%sf(j, k, l)*fluid_pp(i)%gamma
                    pi_inf = pi_inf + q_vf(i + E_idx)%sf(j, k, l)*fluid_pp(i)%pi_inf
                    qv = qv + q_vf(i)%sf(j, k, l)*fluid_pp(i)%qv
                end do
                ! rho    = qK_vf(1)%sf(j,k,l)
                ! gamma_K  = fluid_pp(1)%gamma
                ! pi_inf_K = fluid_pp(1)%pi_inf
            else
                rho = q_vf(1)%sf(j, k, l)
                gamma = fluid_pp(1)%gamma
                pi_inf = fluid_pp(1)%pi_inf
                qv = fluid_pp(1)%qv
            end if
        end if

#ifdef MFC_SIMULATION
        ! Computing the shear and bulk Reynolds numbers from species analogs
        if (any(Re_size > 0)) then
            if (num_fluids == 1) then ! need to consider case with num_fluids >= 2
                do i = 1, 2

                    Re_K(i) = dflt_real; if (Re_size(i) > 0) Re_K(i) = 0._wp

                    do q = 1, Re_size(i)
                        Re_K(i) = (1 - alpha_K(Re_idx(i, q)))/fluid_pp(Re_idx(i, q))%Re(i) &
                                  + Re_K(i)
                    end do

                    Re_K(i) = 1._wp/max(Re_K(i), sgm_eps)

                end do
            end if
        end if
#endif

        ! Post process requires rho_sf/gamma_sf/pi_inf_sf/qv_sf to also be updated
#ifdef MFC_POST_PROCESS
        rho_sf(j, k, l) = rho
        gamma_sf(j, k, l) = gamma
        pi_inf_sf(j, k, l) = pi_inf
        qv_sf(j, k, l) = qv
#endif

    end subroutine s_convert_species_to_mixture_variables_bubbles

    !>  This subroutine is designed for the volume fraction model
        !!              and provided a set of either conservative or primitive
        !!              variables, computes the density, the specific heat ratio
        !!              function and the liquid stiffness function from q_vf and
        !!              stores the results into rho, gamma and pi_inf.
        !! @param q_vf primitive variables
        !! @param k Cell index
        !! @param l Cell index
        !! @param r Cell index
        !! @param rho density
        !! @param gamma specific heat ratio
        !! @param pi_inf liquid stiffness
        !! @param qv fluid reference energy
    subroutine s_convert_species_to_mixture_variables(q_vf, k, l, r, rho, &
                                                      gamma, pi_inf, qv, Re_K, G_K, G)

        type(scalar_field), dimension(sys_size), intent(in) :: q_vf

        integer, intent(in) :: k, l, r

        real(wp), intent(out), target :: rho
        real(wp), intent(out), target :: gamma
        real(wp), intent(out), target :: pi_inf
        real(wp), intent(out), target :: qv

        real(wp), optional, dimension(2), intent(out) :: Re_K
            !! Partial densities and volume fractions
        real(wp), optional, intent(out) :: G_K
        real(wp), optional, dimension(num_fluids), intent(in) :: G

        real(wp), dimension(num_fluids) :: alpha_rho_K, alpha_K !<

        integer :: i, j !< Generic loop iterator

        ! Computing the density, the specific heat ratio function and the
        ! liquid stiffness function, respectively

        do i = 1, num_fluids
            alpha_rho_K(i) = q_vf(i)%sf(k, l, r)
            alpha_K(i) = q_vf(advxb + i - 1)%sf(k, l, r)
        end do

        if (mpp_lim) then

            do i = 1, num_fluids
                alpha_rho_K(i) = max(0._wp, alpha_rho_K(i))
                alpha_K(i) = min(max(0._wp, alpha_K(i)), 1._wp)
            end do

            alpha_K = alpha_K/max(sum(alpha_K), 1e-16_wp)

        end if

        ! Calculating the density, the specific heat ratio function, the
        ! liquid stiffness function, and the energy reference function,
        ! respectively, from the species analogs
        rho = 0._wp; gamma = 0._wp; pi_inf = 0._wp; qv = 0._wp

        do i = 1, num_fluids
            rho = rho + alpha_rho_K(i)
            gamma = gamma + alpha_K(i)*gammas(i)
            pi_inf = pi_inf + alpha_K(i)*pi_infs(i)
            qv = qv + alpha_rho_K(i)*qvs(i)
        end do

#ifdef MFC_SIMULATION
        ! Computing the shear and bulk Reynolds numbers from species analogs
        do i = 1, 2

            Re_K(i) = dflt_real; if (Re_size(i) > 0) Re_K(i) = 0._wp

            do j = 1, Re_size(i)
                Re_K(i) = alpha_K(Re_idx(i, j))/fluid_pp(Re_idx(i, j))%Re(i) &
                          + Re_K(i)
            end do

            Re_K(i) = 1._wp/max(Re_K(i), sgm_eps)

        end do
#endif

        if (present(G_K)) then
            G_K = 0._wp
            do i = 1, num_fluids
                G_K = G_K + alpha_K(i)*G(i)
            end do
            G_K = max(0._wp, G_K)
        end if

        ! Post process requires rho_sf/gamma_sf/pi_inf_sf/qv_sf to also be updated
#ifdef MFC_POST_PROCESS
        rho_sf(k, l, r) = rho
        gamma_sf(k, l, r) = gamma
        pi_inf_sf(k, l, r) = pi_inf
        qv_sf(k, l, r) = qv
#endif

    end subroutine s_convert_species_to_mixture_variables

    subroutine s_convert_species_to_mixture_variables_acc(rho_K, &
                                                          gamma_K, pi_inf_K, qv_K, &
                                                          alpha_K, alpha_rho_K, Re_K, k, l, r, &
                                                          G_K, G)
#ifdef CRAY_ACC_WAR
        !DIR$ INLINEALWAYS s_convert_species_to_mixture_variables_acc
#else
        !$acc routine seq
#endif

        real(wp), intent(out) :: rho_K, gamma_K, pi_inf_K, qv_K

        real(wp), dimension(num_fluids), intent(inout) :: alpha_rho_K, alpha_K !<
        real(wp), dimension(2), intent(out) :: Re_K
        !! Partial densities and volume fractions

        real(wp), optional, intent(out) :: G_K
        real(wp), optional, dimension(num_fluids), intent(in) :: G

        integer, intent(in) :: k, l, r

        integer :: i, j !< Generic loop iterators
        real(wp) :: alpha_K_sum

#ifdef MFC_SIMULATION
        ! Constraining the partial densities and the volume fractions within
        ! their physical bounds to make sure that any mixture variables that
        ! are derived from them result within the limits that are set by the
        ! fluids physical parameters that make up the mixture
        rho_K = 0._wp
        gamma_K = 0._wp
        pi_inf_K = 0._wp
        qv_K = 0._wp

        alpha_K_sum = 0._wp

        if (mpp_lim) then
            do i = 1, num_fluids
                alpha_rho_K(i) = max(0._wp, alpha_rho_K(i))
                alpha_K(i) = min(max(0._wp, alpha_K(i)), 1._wp)
                alpha_K_sum = alpha_K_sum + alpha_K(i)
            end do

            alpha_K = alpha_K/max(alpha_K_sum, sgm_eps)

        end if

        do i = 1, num_fluids
            rho_K = rho_K + alpha_rho_K(i)
            gamma_K = gamma_K + alpha_K(i)*gammas(i)
            pi_inf_K = pi_inf_K + alpha_K(i)*pi_infs(i)
            qv_K = qv_K + alpha_rho_K(i)*qvs(i)
        end do

        if (present(G_K)) then
            G_K = 0._wp
            do i = 1, num_fluids
                !TODO: change to use Gs directly here?
                G_K = G_K + alpha_K(i)*G(i)
            end do
            G_K = max(0._wp, G_K)
        end if

        if (any(Re_size > 0)) then

            do i = 1, 2
                Re_K(i) = dflt_real

                if (Re_size(i) > 0) Re_K(i) = 0._wp

                do j = 1, Re_size(i)
                    Re_K(i) = alpha_K(Re_idx(i, j))/Res(i, j) &
                              + Re_K(i)
                end do

                Re_K(i) = 1._wp/max(Re_K(i), sgm_eps)

            end do
        end if
#endif

    end subroutine s_convert_species_to_mixture_variables_acc

    subroutine s_convert_species_to_mixture_variables_bubbles_acc(rho_K, &
                                                                  gamma_K, pi_inf_K, qv_K, &
                                                                  alpha_K, alpha_rho_K, Re_K, k, l, r)
#ifdef CRAY_ACC_WAR
        !DIR$ INLINEALWAYS s_convert_species_to_mixture_variables_bubbles_acc
#else
        !$acc routine seq
#endif

        real(wp), intent(inout) :: rho_K, gamma_K, pi_inf_K, qv_K

        real(wp), dimension(num_fluids), intent(in) :: alpha_K, alpha_rho_K !<
            !! Partial densities and volume fractions

        real(wp), dimension(2), intent(out) :: Re_K
        integer, intent(in) :: k, l, r

        integer :: i, j !< Generic loop iterators

#ifdef MFC_SIMULATION
        rho_K = 0._wp
        gamma_K = 0._wp
        pi_inf_K = 0._wp
        qv_K = 0._wp

        if (mpp_lim .and. (model_eqns == 2) .and. (num_fluids > 2)) then
            do i = 1, num_fluids
                rho_K = rho_K + alpha_rho_K(i)
                gamma_K = gamma_K + alpha_K(i)*gammas(i)
                pi_inf_K = pi_inf_K + alpha_K(i)*pi_infs(i)
                qv_K = qv_K + alpha_rho_K(i)*qvs(i)
            end do
        else if ((model_eqns == 2) .and. (num_fluids > 2)) then
            do i = 1, num_fluids - 1
                rho_K = rho_K + alpha_rho_K(i)
                gamma_K = gamma_K + alpha_K(i)*gammas(i)
                pi_inf_K = pi_inf_K + alpha_K(i)*pi_infs(i)
                qv_K = qv_K + alpha_rho_K(i)*qvs(i)
            end do
        else
            rho_K = alpha_rho_K(1)
            gamma_K = gammas(1)
            pi_inf_K = pi_infs(1)
            qv_K = qvs(1)
        end if

        if (any(Re_size > 0)) then
            if (num_fluids == 1) then ! need to consider case with num_fluids >= 2

                do i = 1, 2
                    Re_K(i) = dflt_real

                    if (Re_size(i) > 0) Re_K(i) = 0._wp

                    do j = 1, Re_size(i)
                        Re_K(i) = (1._wp - alpha_K(Re_idx(i, j)))/Res(i, j) &
                                  + Re_K(i)
                    end do

                    Re_K(i) = 1._wp/max(Re_K(i), sgm_eps)

                end do
            end if
        end if
#endif

    end subroutine s_convert_species_to_mixture_variables_bubbles_acc

    !>  The computation of parameters, the allocation of memory,
        !!      the association of pointers and/or the execution of any
        !!      other procedures that are necessary to setup the module.
    subroutine s_initialize_variables_conversion_module

        integer :: i, j

#ifdef MFC_PRE_PROCESS
        ixb = 0; iyb = 0; izb = 0; 
        ixe = m; iye = n; ize = p; 
#else
        ixb = -buff_size
        ixe = m - ixb

        iyb = 0; iye = 0; izb = 0; ize = 0; 
        if (n > 0) then
            iyb = -buff_size; iye = n - iyb

            if (p > 0) then
                izb = -buff_size; ize = p - izb
            end if
        end if
#endif

!$acc enter data copyin(ixb, ixe, iyb, iye, izb, ize)
!$acc enter data copyin(is1b, is1e, is2b, is2e, is3b, is3e)
!$acc update device(ixb, ixe, iyb, iye, izb, ize)

#ifdef MFC_SIMULATION
        @:ALLOCATE_GLOBAL(gammas (1:num_fluids))
        @:ALLOCATE_GLOBAL(gs_min (1:num_fluids))
        @:ALLOCATE_GLOBAL(pi_infs(1:num_fluids))
        @:ALLOCATE_GLOBAL(ps_inf(1:num_fluids))
        @:ALLOCATE_GLOBAL(cvs    (1:num_fluids))
        @:ALLOCATE_GLOBAL(qvs    (1:num_fluids))
        @:ALLOCATE_GLOBAL(qvps    (1:num_fluids))
        @:ALLOCATE_GLOBAL(Gs     (1:num_fluids))
#else
        @:ALLOCATE(gammas (1:num_fluids))
        @:ALLOCATE(gs_min (1:num_fluids))
        @:ALLOCATE(pi_infs(1:num_fluids))
        @:ALLOCATE(ps_inf(1:num_fluids))
        @:ALLOCATE(cvs    (1:num_fluids))
        @:ALLOCATE(qvs    (1:num_fluids))
        @:ALLOCATE(qvps    (1:num_fluids))
        @:ALLOCATE(Gs     (1:num_fluids))
#endif

        do i = 1, num_fluids
            gammas(i) = fluid_pp(i)%gamma
            gs_min(i) = 1.0_wp/gammas(i) + 1.0_wp
            pi_infs(i) = fluid_pp(i)%pi_inf
            Gs(i) = fluid_pp(i)%G
            ps_inf(i) = pi_infs(i)/(1.0_wp + gammas(i))
            cvs(i) = fluid_pp(i)%cv
            qvs(i) = fluid_pp(i)%qv
            qvps(i) = fluid_pp(i)%qvp
        end do
!$acc update device(gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps, Gs)

#ifdef MFC_SIMULATION

        if (any(Re_size > 0)) then
            @:ALLOCATE_GLOBAL(Res(1:2, 1:maxval(Re_size)))
            do i = 1, 2
                do j = 1, Re_size(i)
                    Res(i, j) = fluid_pp(Re_idx(i, j))%Re(i)
                end do
            end do

            !$acc update device(Res, Re_idx, Re_size)
        end if
#endif

        if (bubbles) then
#ifdef MFC_SIMULATION
            @:ALLOCATE_GLOBAL(bubrs(1:nb))
#else
            @:ALLOCATE(bubrs(1:nb))
#endif

            do i = 1, nb
                bubrs(i) = bub_idx%rs(i)
            end do

            !$acc update device(bubrs)
        end if

#ifdef MFC_POST_PROCESS
        ! Allocating the density, the specific heat ratio function and the
        ! liquid stiffness function, respectively

        ! Simulation is at least 2D
        if (n > 0) then

            ! Simulation is 3D
            if (p > 0) then

                allocate (rho_sf(-buff_size:m + buff_size, &
                                 -buff_size:n + buff_size, &
                                 -buff_size:p + buff_size))
                allocate (gamma_sf(-buff_size:m + buff_size, &
                                   -buff_size:n + buff_size, &
                                   -buff_size:p + buff_size))
                allocate (pi_inf_sf(-buff_size:m + buff_size, &
                                    -buff_size:n + buff_size, &
                                    -buff_size:p + buff_size))
                allocate (qv_sf(-buff_size:m + buff_size, &
                                -buff_size:n + buff_size, &
                                -buff_size:p + buff_size))

                ! Simulation is 2D
            else

                allocate (rho_sf(-buff_size:m + buff_size, &
                                 -buff_size:n + buff_size, &
                                 0:0))
                allocate (gamma_sf(-buff_size:m + buff_size, &
                                   -buff_size:n + buff_size, &
                                   0:0))
                allocate (pi_inf_sf(-buff_size:m + buff_size, &
                                    -buff_size:n + buff_size, &
                                    0:0))
                allocate (qv_sf(-buff_size:m + buff_size, &
                                -buff_size:n + buff_size, &
                                0:0))
            end if

            ! Simulation is 1D
        else

            allocate (rho_sf(-buff_size:m + buff_size, &
                             0:0, &
                             0:0))
            allocate (gamma_sf(-buff_size:m + buff_size, &
                               0:0, &
                               0:0))
            allocate (pi_inf_sf(-buff_size:m + buff_size, &
                                0:0, &
                                0:0))
            allocate (qv_sf(-buff_size:m + buff_size, &
                            0:0, &
                            0:0))

        end if
#endif

        if (model_eqns == 1) then        ! Gamma/pi_inf model
            s_convert_to_mixture_variables => &
                s_convert_mixture_to_mixture_variables

        else if (bubbles) then
            s_convert_to_mixture_variables => &
                s_convert_species_to_mixture_variables_bubbles
        else
            ! Volume fraction model
            s_convert_to_mixture_variables => &
                s_convert_species_to_mixture_variables
        end if
    end subroutine s_initialize_variables_conversion_module

    !Initialize mv at the quadrature nodes based on the initialized moments and sigma
    subroutine s_initialize_mv(qK_cons_vf, mv)
        type(scalar_field), dimension(sys_size), intent(in) :: qK_cons_vf
        real(wp), dimension(ixb:, iyb:, izb:, 1:, 1:), intent(inout) :: mv

        integer :: i, j, k, l
        real(wp) :: mu, sig, nbub_sc

        do l = izb, ize
            do k = iyb, iye
                do j = ixb, ixe

                    nbub_sc = qK_cons_vf(bubxb)%sf(j, k, l)

                    !$acc loop seq
                    do i = 1, nb
                        mu = qK_cons_vf(bubxb + 1 + (i - 1)*nmom)%sf(j, k, l)/nbub_sc
                        sig = (qK_cons_vf(bubxb + 3 + (i - 1)*nmom)%sf(j, k, l)/nbub_sc - mu**2)**0.5

                        mv(j, k, l, 1, i) = (mass_v0(i))*(mu - sig)**(3._wp)/(R0(i)**(3._wp))
                        mv(j, k, l, 2, i) = (mass_v0(i))*(mu - sig)**(3._wp)/(R0(i)**(3._wp))
                        mv(j, k, l, 3, i) = (mass_v0(i))*(mu + sig)**(3._wp)/(R0(i)**(3._wp))
                        mv(j, k, l, 4, i) = (mass_v0(i))*(mu + sig)**(3._wp)/(R0(i)**(3._wp))
                    end do

                end do
            end do
        end do

    end subroutine s_initialize_mv

    !Initialize pb at the quadrature nodes using isothermal relations (Preston model)
    subroutine s_initialize_pb(qK_cons_vf, mv, pb)
        type(scalar_field), dimension(sys_size), intent(in) :: qK_cons_vf
        real(wp), dimension(ixb:, iyb:, izb:, 1:, 1:), intent(in) :: mv
        real(wp), dimension(ixb:, iyb:, izb:, 1:, 1:), intent(inout) :: pb

        integer :: i, j, k, l
        real(wp) :: mu, sig, nbub_sc

        do l = izb, ize
            do k = iyb, iye
                do j = ixb, ixe

                    nbub_sc = qK_cons_vf(bubxb)%sf(j, k, l)

                    !$acc loop seq
                    do i = 1, nb
                        mu = qK_cons_vf(bubxb + 1 + (i - 1)*nmom)%sf(j, k, l)/nbub_sc
                        sig = (qK_cons_vf(bubxb + 3 + (i - 1)*nmom)%sf(j, k, l)/nbub_sc - mu**2)**0.5

                        !PRESTON (ISOTHERMAL)
                        pb(j, k, l, 1, i) = (pb0(i))*(R0(i)**(3._wp))*(mass_n0(i) + mv(j, k, l, 1, i))/(mu - sig)**(3._wp)/(mass_n0(i) + mass_v0(i))
                        pb(j, k, l, 2, i) = (pb0(i))*(R0(i)**(3._wp))*(mass_n0(i) + mv(j, k, l, 2, i))/(mu - sig)**(3._wp)/(mass_n0(i) + mass_v0(i))
                        pb(j, k, l, 3, i) = (pb0(i))*(R0(i)**(3._wp))*(mass_n0(i) + mv(j, k, l, 3, i))/(mu + sig)**(3._wp)/(mass_n0(i) + mass_v0(i))
                        pb(j, k, l, 4, i) = (pb0(i))*(R0(i)**(3._wp))*(mass_n0(i) + mv(j, k, l, 4, i))/(mu + sig)**(3._wp)/(mass_n0(i) + mass_v0(i))
                    end do
                end do
            end do
        end do

    end subroutine s_initialize_pb

    !> The following procedure handles the conversion between
        !!      the conservative variables and the primitive variables.
        !! @param qK_cons_vf Conservative variables
        !! @param qK_prim_vf Primitive variables
        !! @param gm_alphaK_vf Gradient magnitude of the volume fraction
        !! @param ix Index bounds in first coordinate direction
        !! @param iy Index bounds in second coordinate direction
        !! @param iz Index bounds in third coordinate direction
    subroutine s_convert_conservative_to_primitive_variables(qK_cons_vf, &
                                                             qK_prim_vf, &
                                                             gm_alphaK_vf, &
                                                             ix, iy, iz)

        type(scalar_field), dimension(sys_size), intent(in) :: qK_cons_vf
        type(scalar_field), dimension(sys_size), intent(inout) :: qK_prim_vf
        type(scalar_field), &
            allocatable, optional, dimension(:), &
            intent(in) :: gm_alphaK_vf

        type(int_bounds_info), optional, intent(in) :: ix, iy, iz

        real(wp), dimension(num_fluids) :: alpha_K, alpha_rho_K
        real(wp), dimension(2) :: Re_K
        real(wp) :: rho_K, gamma_K, pi_inf_K, qv_K, dyn_pres_K

        #:if MFC_CASE_OPTIMIZATION
#ifndef MFC_SIMULATION
            real(wp), dimension(:), allocatable :: nRtmp
#else
            real(wp), dimension(nb) :: nRtmp
#endif
        #:else
            real(wp), dimension(:), allocatable :: nRtmp
        #:endif

        real(wp) :: rhoYks(1:num_species)

        real(wp) :: vftmp, nR3, nbub_sc, R3tmp

        real(wp) :: G_K

        real(wp) :: pres, Yksum

        integer :: i, j, k, l, q !< Generic loop iterators

        real(wp) :: ntmp

        #:if MFC_CASE_OPTIMIZATION
#ifndef MFC_SIMULATION
            if (bubbles) then
                allocate (nRtmp(nb))
            else
                allocate (nRtmp(0))
            end if
#endif
        #:else
            if (bubbles) then
                allocate (nRtmp(nb))
            else
                allocate (nRtmp(0))
            end if
        #:endif

        !$acc parallel loop collapse(3) gang vector default(present) private(alpha_K, alpha_rho_K, Re_K, nRtmp, rho_K, gamma_K, pi_inf_K, qv_K, dyn_pres_K, R3tmp, rhoyks)
        do l = izb, ize
            do k = iyb, iye
                do j = ixb, ixe
                    dyn_pres_K = 0._wp

                    !$acc loop seq
                    do i = 1, num_fluids
                        alpha_rho_K(i) = qK_cons_vf(i)%sf(j, k, l)
                        alpha_K(i) = qK_cons_vf(advxb + i - 1)%sf(j, k, l)
                    end do

                    if (model_eqns /= 4) then
#ifdef MFC_SIMULATION
                        ! If in simulation, use acc mixture subroutines
                        if (hypoelasticity) then
                            call s_convert_species_to_mixture_variables_acc(rho_K, gamma_K, pi_inf_K, qv_K, alpha_K, &
                                                                            alpha_rho_K, Re_K, j, k, l, G_K, Gs)
                        else if (bubbles) then
                            call s_convert_species_to_mixture_variables_bubbles_acc(rho_K, gamma_K, pi_inf_K, qv_K, &
                                                                                    alpha_K, alpha_rho_K, Re_K, j, k, l)
                        else
                            call s_convert_species_to_mixture_variables_acc(rho_K, gamma_K, pi_inf_K, qv_K, &
                                                                            alpha_K, alpha_rho_K, Re_K, j, k, l)
                        end if
#else
                        ! If pre-processing, use non acc mixture subroutines
                        if (hypoelasticity) then
                            call s_convert_to_mixture_variables(qK_cons_vf, j, k, l, &
                                                                rho_K, gamma_K, pi_inf_K, qv_K, Re_K, G_K, fluid_pp(:)%G)
                        else
                            call s_convert_to_mixture_variables(qK_cons_vf, j, k, l, &
                                                                rho_K, gamma_K, pi_inf_K, qv_K)
                        end if
#endif
                    end if

                    if (chemistry) then
                        rho_K = 0._wp
                        !$acc loop seq
                        do i = chemxb, chemxe
                            !print*, j,k,l, qK_cons_vf(i)%sf(j, k, l)
                            rho_K = rho_K + max(0._wp, qK_cons_vf(i)%sf(j, k, l))
                        end do

                        !$acc loop seq
                        do i = 1, contxe
                            qK_prim_vf(i)%sf(j, k, l) = rho_K
                        end do

                        Yksum = 0._wp
                        !$acc loop seq
                        do i = chemxb, chemxe
                            qK_prim_vf(i)%sf(j, k, l) = max(0._wp, qK_cons_vf(i)%sf(j, k, l)/rho_K)
                            Yksum = Yksum + qK_prim_vf(i)%sf(j, k, l)
                        end do

                        !$acc loop seq
                        do i = chemxb, chemxe
                            qK_prim_vf(i)%sf(j, k, l) = qK_prim_vf(i)%sf(j, k, l)/Yksum
                        end do

                        qK_prim_vf(tempxb)%sf(j, k, l) = qK_cons_vf(tempxb)%sf(j, k, l)
                    else
                        !$acc loop seq
                        do i = 1, contxe
                            qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l)
                        end do
                    end if

#ifdef MFC_SIMULATION
                    rho_K = max(rho_K, sgm_eps)
#endif

                    !$acc loop seq
                    do i = momxb, momxe
                        if (model_eqns /= 4) then
                            qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l) &
                                                        /rho_K
                            dyn_pres_K = dyn_pres_K + 5e-1_wp*qK_cons_vf(i)%sf(j, k, l) &
                                         *qK_prim_vf(i)%sf(j, k, l)
                        else
                            qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l) &
                                                        /qK_cons_vf(1)%sf(j, k, l)
                        end if
                    end do

                    if (chemistry) then
                        !$acc loop seq
                        do i = 1, num_species
                            rhoYks(i) = qK_cons_vf(chemxb + i - 1)%sf(j, k, l)
                        end do
                    end if

                    call s_compute_pressure(qK_cons_vf(E_idx)%sf(j, k, l), &
                                            qK_cons_vf(alf_idx)%sf(j, k, l), &
                                            dyn_pres_K, pi_inf_K, gamma_K, rho_K, qv_K, rhoYks, pres)

                    qK_prim_vf(E_idx)%sf(j, k, l) = pres

                    if (bubbles) then
                        !$acc loop seq
                        do i = 1, nb
                            nRtmp(i) = qK_cons_vf(bubrs(i))%sf(j, k, l)
                        end do

                        vftmp = qK_cons_vf(alf_idx)%sf(j, k, l)

                        if (qbmm) then
                            !Get nb (constant across all R0 bins)
                            nbub_sc = qK_cons_vf(bubxb)%sf(j, k, l)

                            !Convert cons to prim
                            !$acc loop seq
                            do i = bubxb, bubxe
                                qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l)/nbub_sc
                            end do
                            !Need to keep track of nb in the primitive variable list (converted back to true value before output)
#ifdef MFC_SIMULATION
                            qK_prim_vf(bubxb)%sf(j, k, l) = qK_cons_vf(bubxb)%sf(j, k, l)
#endif

                        else
                            if (adv_n) then
                                qK_prim_vf(n_idx)%sf(j, k, l) = qK_cons_vf(n_idx)%sf(j, k, l)
                                nbub_sc = qK_prim_vf(n_idx)%sf(j, k, l)
                            else
                                call s_comp_n_from_cons(vftmp, nRtmp, nbub_sc, weight)
                            end if

                            !$acc loop seq
                            do i = bubxb, bubxe
                                qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l)/nbub_sc
                            end do
                        end if
                    end if

                    if (hypoelasticity) then
                        !$acc loop seq
                        do i = strxb, strxe
                            qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l) &
                                                        /rho_K
                            ! subtracting elastic contribution for pressure calculation
                            if (G_K > 1000) then !TODO: check if stable for >0
                                qK_prim_vf(E_idx)%sf(j, k, l) = qK_prim_vf(E_idx)%sf(j, k, l) - &
                                                                ((qK_prim_vf(i)%sf(j, k, l)**2._wp)/(4._wp*G_K))/gamma_K
                                ! extra terms in 2 and 3D
                                if ((i == strxb + 1) .or. &
                                    (i == strxb + 3) .or. &
                                    (i == strxb + 4)) then
                                    qK_prim_vf(E_idx)%sf(j, k, l) = qK_prim_vf(E_idx)%sf(j, k, l) - &
                                                                    ((qK_prim_vf(i)%sf(j, k, l)**2._wp)/(4._wp*G_K))/gamma_K
                                end if
                            end if
                        end do
                    end if

                    !$acc loop seq
                    do i = advxb, advxe
                        qK_prim_vf(i)%sf(j, k, l) = qK_cons_vf(i)%sf(j, k, l)
                    end do

                    if (.not. f_is_default(sigma)) then
                        qK_prim_vf(c_idx)%sf(j, k, l) = qK_cons_vf(c_idx)%sf(j, k, l)
                    end if

                end do
            end do
        end do
        !$acc end parallel loop

    end subroutine s_convert_conservative_to_primitive_variables

    !>  The following procedure handles the conversion between
        !!      the primitive variables and the conservative variables.
        !!  @param qK_prim_vf Primitive variables
        !!  @param qK_cons_vf Conservative variables
        !!  @param gm_alphaK_vf Gradient magnitude of the volume fractions
        !!  @param ix Index bounds in the first coordinate direction
        !!  @param iy Index bounds in the second coordinate direction
        !!  @param iz Index bounds in the third coordinate direction
    subroutine s_convert_primitive_to_conservative_variables(q_prim_vf, &
                                                             q_cons_vf)

        type(scalar_field), &
            dimension(sys_size), &
            intent(in) :: q_prim_vf

        type(scalar_field), &
            dimension(sys_size), &
            intent(inout) :: q_cons_vf

        ! Density, specific heat ratio function, liquid stiffness function
        ! and dynamic pressure, as defined in the incompressible flow sense,
        ! respectively
        real(wp) :: rho
        real(wp) :: gamma
        real(wp) :: pi_inf
        real(wp) :: qv
        real(wp) :: dyn_pres
        real(wp) :: nbub, R3, vftmp, R3tmp
        real(wp), dimension(nb) :: Rtmp
        real(wp) :: G = 0._wp
        real(wp), dimension(2) :: Re_K

        integer :: i, j, k, l, q !< Generic loop iterators
        integer :: spec

        real(wp), dimension(num_species) :: Ys
        real(wp) :: temperature, e_mix, mix_mol_weight, T

#ifndef MFC_SIMULATION
        ! Converting the primitive variables to the conservative variables
        do l = 0, p
            do k = 0, n
                do j = 0, m

                    ! Obtaining the density, specific heat ratio function
                    ! and the liquid stiffness function, respectively
                    call s_convert_to_mixture_variables(q_prim_vf, j, k, l, &
                                                        rho, gamma, pi_inf, qv, Re_K, G, fluid_pp(:)%G)

                    ! Transferring the continuity equation(s) variable(s)
                    do i = 1, contxe
                        q_cons_vf(i)%sf(j, k, l) = q_prim_vf(i)%sf(j, k, l)
                    end do

                    ! Transferring the advection equation(s) variable(s)
                    do i = adv_idx%beg, adv_idx%end
                        q_cons_vf(i)%sf(j, k, l) = q_prim_vf(i)%sf(j, k, l)
                    end do

                    ! Zeroing out the dynamic pressure since it is computed
                    ! iteratively by cycling through the velocity equations
                    dyn_pres = 0._wp

                    ! Computing momenta and dynamic pressure from velocity
                    do i = momxb, momxe
                        q_cons_vf(i)%sf(j, k, l) = rho*q_prim_vf(i)%sf(j, k, l)
                        dyn_pres = dyn_pres + q_cons_vf(i)%sf(j, k, l)* &
                                   q_prim_vf(i)%sf(j, k, l)/2._wp
                    end do

                    #:if chemistry
                        do i = chemxb, chemxe
                            Ys(i - chemxb + 1) = q_prim_vf(i)%sf(j, k, l)
                            q_cons_vf(i)%sf(j, k, l) = rho*q_prim_vf(i)%sf(j, k, l)
                        end do

                        call get_mixture_molecular_weight(Ys, mix_mol_weight)
                        T = q_prim_vf(E_idx)%sf(j, k, l)*mix_mol_weight/(gas_constant*rho)
                        call get_mixture_energy_mass(T, Ys, e_mix)

                        q_cons_vf(E_idx)%sf(j, k, l) = &
                            dyn_pres + e_mix

                        q_cons_vf(tempxb)%sf(j, k, l) = T
                    #:else
                        ! Computing the energy from the pressure
                        if ((model_eqns /= 4) .and. (bubbles .neqv. .true.)) then
                            ! E = Gamma*P + \rho u u /2 + \pi_inf + (\alpha\rho qv)
                            q_cons_vf(E_idx)%sf(j, k, l) = &
                                gamma*q_prim_vf(E_idx)%sf(j, k, l) + dyn_pres + pi_inf &
                                + qv
                        else if ((model_eqns /= 4) .and. (bubbles)) then
                            ! \tilde{E} = dyn_pres + (1-\alf)(\Gamma p_l + \Pi_inf)
                            q_cons_vf(E_idx)%sf(j, k, l) = dyn_pres + &
                                                           (1._wp - q_prim_vf(alf_idx)%sf(j, k, l))* &
                                                           (gamma*q_prim_vf(E_idx)%sf(j, k, l) + pi_inf)
                        else
                            !Tait EOS, no conserved energy variable
                            q_cons_vf(E_idx)%sf(j, k, l) = 0.
                        end if
                    #:endif

                    ! Computing the internal energies from the pressure and continuities
                    if (model_eqns == 3) then
                        do i = 1, num_fluids
                            ! internal energy calculation for each of the fluids
                            q_cons_vf(i + internalEnergies_idx%beg - 1)%sf(j, k, l) = &
                                q_cons_vf(i + adv_idx%beg - 1)%sf(j, k, l)* &
                                (fluid_pp(i)%gamma*q_prim_vf(E_idx)%sf(j, k, l) + &
                                 fluid_pp(i)%pi_inf) + &
                                q_cons_vf(i + cont_idx%beg - 1)%sf(j, k, l)*fluid_pp(i)%qv
                        end do
                    end if

                    if (bubbles) then
                        ! From prim: Compute nbub = (3/4pi) * \alpha / \bar{R^3}
                        do i = 1, nb
                            Rtmp(i) = q_prim_vf(bub_idx%rs(i))%sf(j, k, l)
                        end do

                        if (.not. qbmm) then
                            if (adv_n) then
                                q_cons_vf(n_idx)%sf(j, k, l) = q_prim_vf(n_idx)%sf(j, k, l)
                                nbub = q_prim_vf(n_idx)%sf(j, k, l)
                            else
                                call s_comp_n_from_prim(q_prim_vf(alf_idx)%sf(j, k, l), Rtmp, nbub, weight)
                            end if
                        else
                            !Initialize R3 averaging over R0 and R directions
                            R3tmp = 0._wp
                            do i = 1, nb
                                R3tmp = R3tmp + weight(i)*0.5_wp*(Rtmp(i) + sigR)**3._wp
                                R3tmp = R3tmp + weight(i)*0.5_wp*(Rtmp(i) - sigR)**3._wp
                            end do
                            !Initialize nb
                            nbub = 3._wp*q_prim_vf(alf_idx)%sf(j, k, l)/(4._wp*pi*R3tmp)
                        end if

                        if (j == 0 .and. k == 0 .and. l == 0) print *, 'In convert, nbub:', nbub

                        do i = bub_idx%beg, bub_idx%end
                            q_cons_vf(i)%sf(j, k, l) = q_prim_vf(i)%sf(j, k, l)*nbub
                        end do
                    end if

                    if (hypoelasticity) then
                        do i = stress_idx%beg, stress_idx%end
                            q_cons_vf(i)%sf(j, k, l) = rho*q_prim_vf(i)%sf(j, k, l)
                            ! adding elastic contribution
                            if (G > 1000) then
                                q_cons_vf(E_idx)%sf(j, k, l) = q_cons_vf(E_idx)%sf(j, k, l) + &
                                                               (q_prim_vf(i)%sf(j, k, l)**2._wp)/(4._wp*G)
                                ! extra terms in 2 and 3D
                                if ((i == stress_idx%beg + 1) .or. &
                                    (i == stress_idx%beg + 3) .or. &
                                    (i == stress_idx%beg + 4)) then
                                    q_cons_vf(E_idx)%sf(j, k, l) = q_cons_vf(E_idx)%sf(j, k, l) + &
                                                                   (q_prim_vf(i)%sf(j, k, l)**2._wp)/(4._wp*G)
                                end if
                            end if
                        end do
                    end if

                    if (.not. f_is_default(sigma)) then
                        q_cons_vf(c_idx)%sf(j, k, l) = q_prim_vf(c_idx)%sf(j, k, l)
                    end if

                end do
            end do
        end do

#else
        if (proc_rank == 0) then
            call s_mpi_abort('Conversion from primitive to '// &
                             'conservative variables not '// &
                             'implemented. Exiting ...')
        end if
#endif

    end subroutine s_convert_primitive_to_conservative_variables

    !>  The following subroutine handles the conversion between
        !!      the primitive variables and the Eulerian flux variables.
        !!  @param qK_prim_vf Primitive variables
        !!  @param FK_vf Flux variables
        !!  @param FK_src_vf Flux source variables
        !!  @param ix Index bounds in the first coordinate direction
        !!  @param iy Index bounds in the second coordinate direction
        !!  @param iz Index bounds in the third coordinate direction
    subroutine s_convert_primitive_to_flux_variables(qK_prim_vf, &
                                                     FK_vf, &
                                                     FK_src_vf, &
                                                     is1, is2, is3, s2b, s3b)

        integer, intent(in) :: s2b, s3b
        real(wp), dimension(0:, s2b:, s3b:, 1:), intent(in) :: qK_prim_vf
        real(wp), dimension(0:, s2b:, s3b:, 1:), intent(inout) :: FK_vf
        real(wp), dimension(0:, s2b:, s3b:, advxb:), intent(inout) :: FK_src_vf

        type(int_bounds_info), intent(in) :: is1, is2, is3

        ! Partial densities, density, velocity, pressure, energy, advection
        ! variables, the specific heat ratio and liquid stiffness functions,
        ! the shear and volume Reynolds numbers and the Weber numbers
        real(wp), dimension(num_fluids) :: alpha_rho_K
        real(wp), dimension(num_fluids) :: alpha_K
        real(wp) :: rho_K
        real(wp), dimension(num_dims) :: vel_K
        real(wp) :: vel_K_sum
        real(wp) :: pres_K
        real(wp) :: E_K
        real(wp) :: gamma_K
        real(wp) :: pi_inf_K
        real(wp) :: qv_K
        real(wp), dimension(2) :: Re_K
        real(wp) :: G_K

        integer :: i, j, k, l !< Generic loop iterators

        is1b = is1%beg; is1e = is1%end
        is2b = is2%beg; is2e = is2%end
        is3b = is3%beg; is3e = is3%end

        !$acc update device(is1b, is2b, is3b, is1e, is2e, is3e)

        ! Computing the flux variables from the primitive variables, without
        ! accounting for the contribution of either viscosity or capillarity
#ifdef MFC_SIMULATION
        !$acc parallel loop collapse(3) gang vector default(present) private(alpha_rho_K, vel_K, alpha_K, Re_K)
        do l = is3b, is3e
            do k = is2b, is2e
                do j = is1b, is1e

                    !$acc loop seq
                    do i = 1, contxe
                        alpha_rho_K(i) = qK_prim_vf(j, k, l, i)
                    end do

                    !$acc loop seq
                    do i = advxb, advxe
                        alpha_K(i - E_idx) = qK_prim_vf(j, k, l, i)
                    end do
                    !$acc loop seq
                    do i = 1, num_dims
                        vel_K(i) = qK_prim_vf(j, k, l, contxe + i)
                    end do

                    vel_K_sum = 0._wp
                    !$acc loop seq
                    do i = 1, num_dims
                        vel_K_sum = vel_K_sum + vel_K(i)**2._wp
                    end do

                    pres_K = qK_prim_vf(j, k, l, E_idx)
                    if (hypoelasticity) then
                        call s_convert_species_to_mixture_variables_acc(rho_K, gamma_K, pi_inf_K, qv_K, &
                                                                        alpha_K, alpha_rho_K, Re_K, &
                                                                        j, k, l, G_K, Gs)
                    else if (bubbles) then
                        call s_convert_species_to_mixture_variables_bubbles_acc(rho_K, gamma_K, &
                                                                                pi_inf_K, qv_K, alpha_K, alpha_rho_K, Re_K, j, k, l)
                    else
                        call s_convert_species_to_mixture_variables_acc(rho_K, gamma_K, pi_inf_K, qv_K, &
                                                                        alpha_K, alpha_rho_K, Re_K, j, k, l)
                    end if

                    ! Computing the energy from the pressure
                    E_K = gamma_K*pres_K + pi_inf_K &
                          + 5e-1_wp*rho_K*vel_K_sum + qv_K

                    ! mass flux, this should be \alpha_i \rho_i u_i
                    !$acc loop seq
                    do i = 1, contxe
                        FK_vf(j, k, l, i) = alpha_rho_K(i)*vel_K(dir_idx(1))
                    end do

                    !$acc loop seq
                    do i = 1, num_dims
                        FK_vf(j, k, l, contxe + dir_idx(i)) = &
                            rho_K*vel_K(dir_idx(1)) &
                            *vel_K(dir_idx(i)) &
                            + pres_K*dir_flg(dir_idx(i))
                    end do

                    ! energy flux, u(E+p)
                    FK_vf(j, k, l, E_idx) = vel_K(dir_idx(1))*(E_K + pres_K)

                    if (riemann_solver == 1) then
                        !$acc loop seq
                        do i = advxb, advxe
                            FK_vf(j, k, l, i) = 0._wp
                            FK_src_vf(j, k, l, i) = alpha_K(i - E_idx)
                        end do

                    else
                        ! Could be bubbles!
                        !$acc loop seq
                        do i = advxb, advxe
                            FK_vf(j, k, l, i) = vel_K(dir_idx(1))*alpha_K(i - E_idx)
                        end do

                        !$acc loop seq
                        do i = advxb, advxe
                            FK_src_vf(j, k, l, i) = vel_K(dir_idx(1))
                        end do

                    end if

                end do
            end do
        end do
#endif

    end subroutine s_convert_primitive_to_flux_variables

    subroutine s_finalize_variables_conversion_module

        ! Deallocating the density, the specific heat ratio function and the
        ! liquid stiffness function
#ifdef MFC_POST_PROCESS
        deallocate (rho_sf, gamma_sf, pi_inf_sf, qv_sf)
#endif

#ifdef MFC_SIMULATION
        @:DEALLOCATE_GLOBAL(gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps, Gs)
        if (bubbles) then
            @:DEALLOCATE_GLOBAL(bubrs)
        end if
#else
        @:DEALLOCATE(gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps, Gs)
        if (bubbles) then
            @:DEALLOCATE(bubrs)
        end if
#endif

        ! Nullifying the procedure pointer to the subroutine transferring/
        ! computing the mixture/species variables to the mixture variables
        s_convert_to_mixture_variables => null()

    end subroutine s_finalize_variables_conversion_module

#ifndef MFC_PRE_PROCESS
    subroutine s_compute_speed_of_sound(pres, rho, gamma, pi_inf, H, adv, vel_sum, c)
#ifdef CRAY_ACC_WAR
        !DIR$ INLINEALWAYS s_compute_speed_of_sound
#else
        !$acc routine seq
#endif
        real(wp), intent(in) :: pres
        real(wp), intent(in) :: rho, gamma, pi_inf
        real(wp), intent(in) :: H
        real(wp), dimension(num_fluids), intent(in) :: adv
        real(wp), intent(in) :: vel_sum
        real(wp), intent(out) :: c

        real(wp) :: blkmod1, blkmod2

        integer :: q

        if (alt_soundspeed) then
            blkmod1 = ((gammas(1) + 1._wp)*pres + &
                       pi_infs(1))/gammas(1)
            blkmod2 = ((gammas(2) + 1._wp)*pres + &
                       pi_infs(2))/gammas(2)
            c = (1._wp/(rho*(adv(1)/blkmod1 + adv(2)/blkmod2)))
        elseif (model_eqns == 3) then
            c = 0._wp
            !$acc loop seq
            do q = 1, num_fluids
                c = c + adv(q)*(1._wp/gammas(q) + 1._wp)* &
                    (pres + pi_infs(q)/(gammas(q) + 1._wp))
            end do
            c = c/rho

        elseif (((model_eqns == 4) .or. (model_eqns == 2 .and. bubbles))) then
            ! Sound speed for bubble mmixture to order O(\alpha)

            if (mpp_lim .and. (num_fluids > 1)) then
                c = (1._wp/gamma + 1._wp)* &
                    (pres + pi_inf/(gamma + 1._wp))/rho
            else
                c = &
                    (1._wp/gamma + 1._wp)* &
                    (pres + pi_inf/(gamma + 1._wp))/ &
                    (rho*(1._wp - adv(num_fluids)))
            end if
        else
            c = ((H - 5e-1_wp*vel_sum)/gamma)
        end if

        if (mixture_err .and. c < 0._wp) then
            c = 100._wp*sgm_eps
        else
            c = sqrt(c)
        end if
    end subroutine s_compute_speed_of_sound
#endif

end module m_variables_conversion
