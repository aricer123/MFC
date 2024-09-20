#:include 'macros.fpp'
!>
!! @file m_helper.f90
!! @brief Contains module m_helper

module m_helper

    ! Dependencies =============================================================

    use m_derived_types        !< Definitions of the derived types

    use m_global_parameters    !< Definitions of the global parameters

    use m_mpi_common           !< MPI modules

    use ieee_arithmetic        !< For checking NaN

    ! ==========================================================================

    implicit none

    private; 
    public :: s_comp_n_from_prim, &
              s_comp_n_from_cons, &
              s_initialize_nonpoly, &
              s_simpson, &
              s_transcoeff, &
              s_int_to_str, &
              s_transform_vec, &
              s_transform_triangle, &
              s_transform_model, &
              s_swap, &
              f_cross, &
              f_create_transform_matrix, &
              f_create_bbox, &
              s_print_2D_array, &
              f_xor, &
              f_logical_to_int, &
              s_prohibit_abort

contains

    !> Computes the bubble number density n from the primitive variables
        !! @param vftmp is the void fraction
        !! @param Rtmp is the  bubble radii
        !! @param ntmp is the output number bubble density
    subroutine s_comp_n_from_prim(vftmp, Rtmp, ntmp, weights)
        !$acc routine seq
        real(wp), intent(in) :: vftmp
        real(wp), dimension(nb), intent(in) :: Rtmp
        real(wp), intent(out) :: ntmp
        real(wp), dimension(nb), intent(in) :: weights

        real(wp) :: R3

        R3 = dot_product(weights, Rtmp**3._wp)
        ntmp = (3._wp/(4._wp*pi))*vftmp/R3

    end subroutine s_comp_n_from_prim

    subroutine s_comp_n_from_cons(vftmp, nRtmp, ntmp, weights)
        !$acc routine seq
        real(wp), intent(in) :: vftmp
        real(wp), dimension(nb), intent(in) :: nRtmp
        real(wp), intent(out) :: ntmp
        real(wp), dimension(nb), intent(in) :: weights

        real(wp) :: nR3

        nR3 = dot_product(weights, nRtmp**3._wp)
        ntmp = DSQRT((4._wp*pi/3._wp)*nR3/vftmp)
        !ntmp = (3._wp/(4._wp*pi))*0.00001

        !print *, "nbub", ntmp

    end subroutine s_comp_n_from_cons

    subroutine s_print_2D_array(A, div)

        real(wp), dimension(:, :), intent(in) :: A
        real, optional, intent(in) :: div

        integer :: i, j
        integer :: m, n
        real :: c

        m = size(A, 1)
        n = size(A, 2)

        if (present(div)) then
            c = div
        else
            c = 1
        end if

        print *, m, n

        do i = 1, m
            do j = 1, n
                write (*, fmt="(F12.4)", advance="no") A(i, j)/c
            end do
            write (*, fmt="(A1)") " "
        end do
        write (*, fmt="(A1)") " "

    end subroutine

    !> Initializes non-polydisperse bubble modeling
    subroutine s_initialize_nonpoly

        integer :: ir
        real(wp) :: rhol0, pl0, uu, D_m, temp, omega_ref
        real(wp), dimension(Nb) :: chi_vw0, cp_m0, k_m0, rho_m0, x_vw

        real(wp), parameter :: k_poly = 1._wp !<
            !! polytropic index used to compute isothermal natural frequency

        real(wp), parameter :: Ru = 8314._wp !<
            !! universal gas constant

        rhol0 = rhoref
        pl0 = pref
#ifdef MFC_SIMULATION
        @:ALLOCATE_GLOBAL(pb0(nb), mass_n0(nb), mass_v0(nb), Pe_T(nb))
        @:ALLOCATE_GLOBAL(k_n(nb), k_v(nb), omegaN(nb))
        @:ALLOCATE_GLOBAL(Re_trans_T(nb), Re_trans_c(nb), Im_trans_T(nb), Im_trans_c(nb))
#else
        @:ALLOCATE(pb0(nb), mass_n0(nb), mass_v0(nb), Pe_T(nb))
        @:ALLOCATE(k_n(nb), k_v(nb), omegaN(nb))
        @:ALLOCATE(Re_trans_T(nb), Re_trans_c(nb), Im_trans_T(nb), Im_trans_c(nb))
#endif

        pb0(:) = dflt_real
        mass_n0(:) = dflt_real
        mass_v0(:) = dflt_real
        Pe_T(:) = dflt_real
        omegaN(:) = dflt_real

        mul0 = fluid_pp(1)%mul0
        ss = fluid_pp(1)%ss
        pv = fluid_pp(1)%pv
        gamma_v = fluid_pp(1)%gamma_v
        M_v = fluid_pp(1)%M_v
        mu_v = fluid_pp(1)%mu_v
        k_v(:) = fluid_pp(1)%k_v

        gamma_n = fluid_pp(2)%gamma_v
        M_n = fluid_pp(2)%M_v
        mu_n = fluid_pp(2)%mu_v
        k_n(:) = fluid_pp(2)%k_v

        gamma_m = gamma_n
        if (thermal == 2) gamma_m = 1._wp

        temp = 293.15_wp
        D_m = 0.242d-4
        uu = DSQRT(pl0/rhol0)

        omega_ref = 3._wp*k_poly*Ca + 2._wp*(3._wp*k_poly - 1._wp)/Web

            !!! thermal properties !!!
        ! gas constants
        R_n = Ru/M_n
        R_v = Ru/M_v
        ! phi_vn & phi_nv (phi_nn = phi_vv = 1)
        phi_vn = (1._wp + DSQRT(mu_v/mu_n)*(M_n/M_v)**(0.25_wp))**2 &
                 /(DSQRT(8._wp)*DSQRT(1._wp + M_v/M_n))
        phi_nv = (1._wp + DSQRT(mu_n/mu_v)*(M_v/M_n)**(0.25_wp))**2 &
                 /(DSQRT(8._wp)*DSQRT(1._wp + M_n/M_v))
        ! internal bubble pressure
        pb0 = pl0 + 2._wp*ss/(R0ref*R0)

        ! mass fraction of vapor
        chi_vw0 = 1._wp/(1._wp + R_v/R_n*(pb0/pv - 1._wp))
        ! specific heat for gas/vapor mixture
        cp_m0 = chi_vw0*R_v*gamma_v/(gamma_v - 1._wp) &
                + (1._wp - chi_vw0)*R_n*gamma_n/(gamma_n - 1._wp)
        ! mole fraction of vapor
        x_vw = M_n*chi_vw0/(M_v + (M_n - M_v)*chi_vw0)
        ! thermal conductivity for gas/vapor mixture
        k_m0 = x_vw*k_v/(x_vw + (1._wp - x_vw)*phi_vn) &
               + (1._wp - x_vw)*k_n/(x_vw*phi_nv + 1._wp - x_vw)
        ! mixture density
        rho_m0 = pv/(chi_vw0*R_v*temp)

        ! mass of gas/vapor computed using dimensional quantities
        mass_n0 = 4._wp*(pb0 - pv)*pi/(3._wp*R_n*temp*rhol0)*R0**3
        mass_v0 = 4._wp*pv*pi/(3._wp*R_v*temp*rhol0)*R0**3
        ! Peclet numbers
        Pe_T = rho_m0*cp_m0*uu*R0ref/k_m0
        Pe_c = uu*R0ref/D_m

        Tw = temp

        ! nondimensional properties
        !if(.not. qbmm) then
        R_n = rhol0*R_n*temp/pl0
        R_v = rhol0*R_v*temp/pl0
        k_n = k_n/k_m0
        k_v = k_v/k_m0
        pb0 = pb0/pl0
        pv = pv/pl0
        Tw = 1._wp
        pl0 = 1._wp

        rhoref = 1._wp
        pref = 1._wp
        !end if

        ! natural frequencies
        omegaN = DSQRT(3._wp*k_poly*Ca + 2._wp*(3._wp*k_poly - 1._wp)/(Web*R0))/R0
        do ir = 1, Nb
            call s_transcoeff(omegaN(ir)*R0(ir), Pe_T(ir)*R0(ir), &
                              Re_trans_T(ir), Im_trans_T(ir))
            call s_transcoeff(omegaN(ir)*R0(ir), Pe_c*R0(ir), &
                              Re_trans_c(ir), Im_trans_c(ir))
        end do
        Im_trans_T = 0._wp

    end subroutine s_initialize_nonpoly

    !> Computes the transfer coefficient for the non-polytropic bubble compression process
        !! @param omega natural frqeuencies
        !! @param peclet Peclet number
        !! @param Re_trans Real part of the transport coefficients
        !! @param Im_trans Imaginary part of the transport coefficients
    subroutine s_transcoeff(omega, peclet, Re_trans, Im_trans)

        real(wp), intent(in) :: omega, peclet
        real(wp), intent(out) :: Re_trans, Im_trans

        complex :: trans, c1, c2, c3
        complex :: imag = (0., 1.)
        real(wp) :: f_transcoeff

        c1 = imag*omega*peclet
        c2 = CSQRT(c1)
        c3 = (CEXP(c2) - CEXP(-c2))/(CEXP(c2) + CEXP(-c2)) ! TANH(c2)
        trans = ((c2/c3 - 1._wp)**(-1) - 3._wp/c1)**(-1) ! transfer function

        Re_trans = dble(trans)
        Im_trans = aimag(trans)

    end subroutine s_transcoeff

    subroutine s_int_to_str(i, res)

        integer, intent(in) :: i
        character(len=*), intent(out) :: res

        write (res, '(I0)') i
        res = trim(res)
    end subroutine

    !> Computes the Simpson weights for quadrature
    subroutine s_simpson

        integer :: ir
        real(wp) :: R0mn, R0mx, dphi, tmp, sd
        real(wp), dimension(nb) :: phi

        ! nondiml. min. & max. initial radii for numerical quadrature
        !sd   = 0.05D0
        !R0mn = 0.75D0
        !R0mx = 1.3D0

        !sd   = 0.3D0
        !R0mn = 0.3D0
        !R0mx = 6.D0

        !sd   = 0.7D0
        !R0mn = 0.12D0
        !R0mx = 150.D0

        sd = poly_sigma
        R0mn = 0.8_wp*DEXP(-2.8_wp*sd)
        R0mx = 0.2_wp*DEXP(9.5_wp*sd) + 1._wp

        ! phi = ln( R0 ) & return R0
        do ir = 1, nb
            phi(ir) = DLOG(R0mn) &
                      + dble(ir - 1)*DLOG(R0mx/R0mn)/dble(nb - 1)
            R0(ir) = DEXP(phi(ir))
        end do
        dphi = phi(2) - phi(1)

        ! weights for quadrature using Simpson's rule
        do ir = 2, nb - 1
            ! Gaussian
            tmp = DEXP(-0.5_wp*(phi(ir)/sd)**2)/DSQRT(2._wp*pi)/sd
            if (mod(ir, 2) == 0) then
                weight(ir) = tmp*4._wp*dphi/3._wp
            else
                weight(ir) = tmp*2._wp*dphi/3._wp
            end if
        end do
        tmp = DEXP(-0.5_wp*(phi(1)/sd)**2)/DSQRT(2._wp*pi)/sd
        weight(1) = tmp*dphi/3._wp
        tmp = DEXP(-0.5_wp*(phi(nb)/sd)**2)/DSQRT(2._wp*pi)/sd
        weight(nb) = tmp*dphi/3._wp
    end subroutine s_simpson

    !> This procedure computes the cross product of two vectors.
    !! @param a First vector.
    !! @param b Second vector.
    !! @return The cross product of the two vectors.
    function f_cross(a, b) result(c)

        real(wp), dimension(3), intent(in) :: a, b
        real(wp), dimension(3) :: c

        c(1) = a(2)*b(3) - a(3)*b(2)
        c(2) = a(3)*b(1) - a(1)*b(3)
        c(3) = a(1)*b(2) - a(2)*b(1)
    end function f_cross

    !> This procedure swaps two real numbers.
    !! @param lhs Left-hand side.
    !! @param rhs Right-hand side.
    subroutine s_swap(lhs, rhs)

        real(wp), intent(inout) :: lhs, rhs
        real(wp) :: ltemp

        ltemp = lhs
        lhs = rhs
        rhs = ltemp
    end subroutine s_swap

    !> This procedure creates a transformation matrix.
    !! @param  p Parameters for the transformation.
    !! @return Transformation matrix.
    function f_create_transform_matrix(p) result(out_matrix)

        type(ic_model_parameters), intent(in) :: p
        t_mat4x4 :: sc, rz, rx, ry, tr, out_matrix

        sc = transpose(reshape([ &
                               p%scale(1), 0._wp, 0._wp, 0._wp, &
                               0._wp, p%scale(2), 0._wp, 0._wp, &
                               0._wp, 0._wp, p%scale(3), 0._wp, &
                               0._wp, 0._wp, 0._wp, 1._wp], shape(sc)))

        rz = transpose(reshape([ &
                               cos(p%rotate(3)), -sin(p%rotate(3)), 0._wp, 0._wp, &
                               sin(p%rotate(3)), cos(p%rotate(3)), 0._wp, 0._wp, &
                               0._wp, 0._wp, 1._wp, 0._wp, &
                               0._wp, 0._wp, 0._wp, 1._wp], shape(rz)))

        rx = transpose(reshape([ &
                               1._wp, 0._wp, 0._wp, 0._wp, &
                               0._wp, cos(p%rotate(1)), -sin(p%rotate(1)), 0._wp, &
                               0._wp, sin(p%rotate(1)), cos(p%rotate(1)), 0._wp, &
                               0._wp, 0._wp, 0._wp, 1._wp], shape(rx)))

        ry = transpose(reshape([ &
                               cos(p%rotate(2)), 0._wp, sin(p%rotate(2)), 0._wp, &
                               0._wp, 1._wp, 0._wp, 0._wp, &
                               -sin(p%rotate(2)), 0._wp, cos(p%rotate(2)), 0._wp, &
                               0._wp, 0._wp, 0._wp, 1._wp], shape(ry)))

        tr = transpose(reshape([ &
                               1._wp, 0._wp, 0._wp, p%translate(1), &
                               0._wp, 1._wp, 0._wp, p%translate(2), &
                               0._wp, 0._wp, 1._wp, p%translate(3), &
                               0._wp, 0._wp, 0._wp, 1._wp], shape(tr)))

        out_matrix = matmul(tr, matmul(ry, matmul(rx, matmul(rz, sc))))

    end function f_create_transform_matrix

    !> This procedure transforms a vector by a matrix.
    !! @param vec Vector to transform.
    !! @param matrix Transformation matrix.
    subroutine s_transform_vec(vec, matrix)

        t_vec3, intent(inout) :: vec
        t_mat4x4, intent(in) :: matrix

        real(wp), dimension(1:4) :: tmp

        tmp = matmul(matrix, [vec(1), vec(2), vec(3), 1._wp])
        vec = tmp(1:3)

    end subroutine s_transform_vec

    !> This procedure transforms a triangle by a matrix, one vertex at a time.
    !! @param triangle Triangle to transform.
    !! @param matrix   Transformation matrix.
    subroutine s_transform_triangle(triangle, matrix)

        type(t_triangle), intent(inout) :: triangle
        t_mat4x4, intent(in) :: matrix

        integer :: i

        real(wp), dimension(1:4) :: tmp

        do i = 1, 3
            call s_transform_vec(triangle%v(i, :), matrix)
        end do

    end subroutine s_transform_triangle

    !> This procedure transforms a model by a matrix, one triangle at a time.
    !! @param model  Model to transform.
    !! @param matrix Transformation matrix.
    subroutine s_transform_model(model, matrix)

        type(t_model), intent(inout) :: model
        t_mat4x4, intent(in) :: matrix

        integer :: i

        do i = 1, size(model%trs)
            call s_transform_triangle(model%trs(i), matrix)
        end do

    end subroutine s_transform_model

    !> This procedure creates a bounding box for a model.
    !! @param model Model to create bounding box for.
    !! @return Bounding box.
    function f_create_bbox(model) result(bbox)

        type(t_model), intent(in) :: model
        type(t_bbox) :: bbox

        integer :: i, j

        if (size(model%trs) == 0) then
            bbox%min = 0._wp
            bbox%max = 0._wp
            return
        end if

        bbox%min = model%trs(1)%v(1, :)
        bbox%max = model%trs(1)%v(1, :)

        do i = 1, size(model%trs)
            do j = 1, 3
                bbox%min = min(bbox%min, model%trs(i)%v(j, :))
                bbox%max = max(bbox%max, model%trs(i)%v(j, :))
            end do
        end do

    end function f_create_bbox

    function f_xor(lhs, rhs) result(res)

        logical, intent(in) :: lhs, rhs
        logical :: res

        res = (lhs .and. .not. rhs) .or. (.not. lhs .and. rhs)
    end function f_xor

    function f_logical_to_int(predicate) result(int)

        logical, intent(in) :: predicate
        integer :: int

        if (predicate) then
            int = 1
        else
            int = 0
        end if
    end function f_logical_to_int

    subroutine s_prohibit_abort(condition, message)
        character(len=*), intent(in) :: condition, message

        print *, ""
        print *, "===================================================================================================="
        print *, "                                          CASE FILE ERROR                                           "
        print *, "----------------------------------------------------------------------------------------------------"
        print *, "Prohibited condition: ", trim(condition)
        if (len_trim(message) > 0) then
            print *, "Note: ", trim(message)
        end if
        print *, "===================================================================================================="
        print *, ""
        call s_mpi_abort
    end subroutine s_prohibit_abort

end module m_helper
